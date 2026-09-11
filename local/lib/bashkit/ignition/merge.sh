# shellcheck shell=bash
#
# Core ignition merge/compile/hash pipeline: compiles butane configs to ignition JSON via a
# containerized butane, inlines subordinate .ignition.config.merge[] entries with verification
# hashes, and loads secrets/env files consumed by that pipeline.

readonly __BASHKIT_LIB_IGNITION_MERGE_SOURCED="true"

if [[ "$(declare -p __empty_array 2>/dev/null)" != "declare -a"* ]]; then
  declare -ar __empty_array=()
fi
declare -r __empty_array_ref='__empty_array'

# ignition_gen()
#
# Compiles a single butane (.bu) file to ignition JSON by running
# quay.io/coreos/butane:release in a podman container. The directory
# containing the .bu file is mounted as the container workdir so that
# local file references in the config (e.g. under a "files" sub-directory)
# resolve correctly.
#
# Globals:
#   __BASHKIT_LIB_BUTANE_CONTAINER_WORKDIR   Container workdir path secret mounts are
#         resolved under.
# Arguments:
#   1) butane_path   - relative path to a .bu file (e.g. deploy/butane/base/root.bu).
#         The file's parent directory is mounted into the container; only files at
#         the same depth or below are reachable by butane's --files-dir resolution.
#   2) secret_names  - nameref (optional); array of podman secret names to mount into
#         the butane container at ${__BASHKIT_LIB_BUTANE_CONTAINER_WORKDIR}/files/secrets/<name>.
# Outputs:
#   Writes the compiled ignition JSON to stdout; an log_error message to the log on failure.
# Returns:
#   1 if butane compilation fails; 0 otherwise.
ignition::gen() {
  # 1>&2: this function's stdout is its return channel (compiled ignition JSON) -- any
  # console-level log write on stdout here would corrupt it. See the note on the removed
  # INFO-level log call below.
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))" 1>&2

  core::require_operands 1 "$@" || return 1
  local -r butane_path="$1"
  local -n _secret_names_ref="${2:-"${__empty_array_ref}"}"

  local -r files_dir="files"
  local -a butane_opts=()
  # shellcheck disable=SC2034
  if [[ -v _secret_names_ref ]]; then
    local s
    for s in "${_secret_names_ref[@]}"; do
      butane_opts+=(
        "-s"
        "${s},type=mount,target=${__BASHKIT_LIB_BUTANE_CONTAINER_WORKDIR}/${files_dir}/secrets/${s}"
      )
    done
  fi

  butane_opts+=(
    "-m"
    "${PWD}/$(dirname "${butane_path}")"
    --
    "--strict"
    "--files-dir=${files_dir}"
    "--raw"
    "$(basename "${butane_path}")"
  )

  # Not an INFO-level log: this function's stdout is its return channel (compiled ignition JSON,
  # captured via `$(...)` by ignition_merge_compile_entry()) -- any console-level log write
  # here would corrupt that output. The caller already logs this at DEBUG before calling in.
  if ! ignition::butane "${butane_opts[@]}"; then
    log_error "ignition generation failed for ${butane_path}"
    return 1
  fi
}

# ignition_merge_read_inline_path()
#
# Reads the "inline" field at .ignition.config.merge[idx] from config_json --
# the relative path to that merge entry's subordinate .bu file. Performs a
# bounds check on idx against merge_jq_path first, via the shared bounds_check
# jq def, halting with jq's halt_log_error if idx is out of range.
#
# Arguments:
#   1) config_json     - the in-progress merged butane config, as compact JSON.
#   2) merge_jq_path   - compact JSON array addressing .ignition.config.merge[]
#         (e.g. ["ignition","config","merge"]).
#   3) idx             - integer index of the entry to read within the merge array.
#   4) jq_bounds_check - jq `def bounds_check(expr): ...;` snippet shared with
#         ignition_merge_write_entry()'s jq call.
# Outputs:
#   Writes the subordinate .bu file path to stdout.
# Returns:
#   1 if idx is out of bounds (jq halt_error) or the jq invocation fails; 0 otherwise.
ignition::merge_read_inline_path() {
  # $1 (config_json) accumulates inlined secrets as the merge loop in
  # ignition_gen_config_merge_inlines() progresses, so it's redacted here rather than
  # dumped via $* -- everything else about the call is still worth tracing normally.
  log_debug "Starting ${FUNCNAME[0]}(<config_json redacted> $2 $3 $4)"

  core::require_operands 4 "$@" || return 1
  local -r config_json="$1"
  local -r merge_jq_path="$2"
  local -ri idx="$3"
  local -r jq_bounds_check="$4"

  # Extend the merge path with the current index and the "inline" key.
  # e.g. ["ignition","config","merge",0,"inline"]
  local inline_jq_path
  inline_jq_path="$(jq -c --argjson idx "${idx}" '. += [$idx, "inline"]' \
    <<< "${merge_jq_path}")"

  jq -r --argjson merge_jq_path  "${merge_jq_path}" \
    --argjson idx            "${idx}" \
    --argjson inline_jq_path "${inline_jq_path}" \
    "${jq_bounds_check} bounds_check(getpath(\$inline_jq_path))" \
    <<< "${config_json}"
}

# ignition_merge_compile_entry()
#
# Compiles butane_file_path to ignition JSON via ignition_gen(), then hashes
# the result with sha512sum_gen_stdin and formats it as an Ignition
# verification.hash value via checksum_format_verification_hash_sha512().
# Results are returned via nameref args (not stdout) so that a fatal() on
# failure terminates the caller's shell directly, rather than only the
# subshell a stdout-capturing caller would fork.
#
# Arguments:
#   1) butane_file_path      - relative path to a .bu file.
#   2) ignition_json_out     - nameref; receives the compiled ignition JSON string.
#   3) verification_hash_out - nameref; receives the "sha512-<hex>" formatted hash of
#         ignition_json_out.
#   4) secret_names           - nameref name (optional, may be empty); array of podman
#         secret names passed through to ignition_gen() for mounting secrets inside
#         the butane container.
# Outputs:
#   Error messages to the log on failure.
# Returns:
#   1 if ignition_gen() or hash generation fails; 0 otherwise.
ignition::merge_compile_entry() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 3 "$@" || return 1
  local -r butane_file_path="$1"
  local -n ignition_json_out="$2"
  local -n verification_hash_out="$3"
  # This is assigned as a string to pass the nameref from the above scope without creating another nameref.
  # Preventing circular namerefs.
  local -r secrets="${4:-"${__empty_array_ref}"}"

  log_debug "Generating ignition: ${butane_file_path}"
  if ! ignition_json_out="$(ignition::gen "${butane_file_path}" "${secrets}")"; then
    log_error "failed to generate ignition config from: ${butane_file_path}"
    return 1
  fi

  log_debug "Generating verification hash: ${butane_file_path}"
  # printf '%s' (no here-string): a here-string would append a trailing newline before
  # hashing, but ignition_merge_write_entry() embeds ignition_json_out verbatim via
  # printf '%s' (no trailing newline) -- the hash must cover the exact bytes that get
  # embedded, or Ignition rejects the merge config with a verification hash mismatch.
  # shellcheck disable=SC2034,SC2119
  if ! verification_hash_out="$(printf '%s' "${ignition_json_out}" \
    | core::sha512sum_gen_stdin \
    | core::checksum_format_verification_hash_sha512)"; then

    log_error "failed to generate verification hash for: ${butane_file_path}"
    return 1
  fi
}

# ignition_merge_write_entry()
#
# Writes ignition_json into .ignition.config.merge[idx].inline and
# verification_hash into .ignition.config.merge[idx].verification.hash within
# config_json. Performs the same bounds check on idx as
# ignition_merge_read_inline_path(). Output is written to stdout.
#
# Arguments:
#   1) config_json       - the in-progress merged butane config, as compact JSON.
#   2) merge_jq_path     - compact JSON array addressing .ignition.config.merge[].
#   3) idx               - integer index of the entry to update within the merge array.
#   4) jq_bounds_check   - jq `def bounds_check(expr): ...;` snippet shared with
#         ignition_merge_read_inline_path()'s jq call.
#   5) ignition_json     - compiled ignition JSON to inline at this entry.
#   6) verification_hash - "sha512-<hex>" formatted hash of ignition_json.
# Outputs:
#   Writes config_json with the merge entry updated in place, to stdout.
# Returns:
#   1 if idx is out of bounds (jq halt_error) or a jq invocation fails; 0 otherwise.
ignition::merge_write_entry() {
  # $1 (config_json) and $5 (ignition_json) may carry secret-bearing content, so both are
  # redacted here rather than dumped via $* -- everything else is still traced normally.
  log_debug "Starting ${FUNCNAME[0]}(<config_json redacted> $2 $3 $4 <ignition_json redacted> $6)"

  core::require_operands 6 "$@" || return 1
  local -r config_json="$1"
  local -r merge_jq_path="$2"
  local -ri idx="$3"
  local -r jq_bounds_check="$4"
  local -r ignition_json="$5"
  local -r verification_hash="$6"

  # Extend the merge path with the current index and the "inline" key,
  # and again with the "verification","hash" keys.
  # e.g. ["ignition","config","merge",0,"inline"]
  # e.g. ["ignition","config","merge",0,"verification","hash"]
  local inline_jq_path verification_hash_jq_path
  inline_jq_path="$(jq -c --argjson idx "${idx}" '. += [$idx, "inline"]' \
    <<< "${merge_jq_path}")"
  verification_hash_jq_path="$(jq -c --argjson idx "${idx}" \
    '. += [$idx, "verification", "hash"]' \
    <<< "${merge_jq_path}")"

  log_debug "Updating inline entry [${idx}]: ${inline_jq_path}"
  jq -rc --argjson merge_jq_path             "${merge_jq_path}" \
    --argjson idx                       "${idx}" \
    --argjson inline_jq_path            "${inline_jq_path}" \
    --argjson verification_hash_jq_path "${verification_hash_jq_path}" \
    --rawfile new_value <(printf '%s' "${ignition_json}") \
    --arg verification_hash "${verification_hash}" \
    "${jq_bounds_check} bounds_check(getpath(\$inline_jq_path) = \$new_value | \
getpath(\$verification_hash_jq_path) = \$verification_hash)" \
    <<< "${config_json}"
}

# ignition_gen_config_merge_inlines()
#
# Reads the top-level butane config at butane_path, then for every subordinate
# .bu file path listed under .ignition.config.merge[].inline: reads the path
# via ignition_merge_read_inline_path(), compiles and hashes it via
# ignition_merge_compile_entry(), and writes the resulting ignition JSON plus
# its verification.hash back into the config via ignition_merge_write_entry().
# The fully merged document is then compiled once more via butane to produce
# the final ignition JSON.
#
# Arguments:
#   1) butane_path - path to the top-level butane config (e.g. main.bu). Must
#         contain an .ignition.config.merge[] array whose entries each have an
#         "inline" field holding a relative path to a subordinate .bu file.
#   2) out         - nameref; receives the final merged ignition JSON string on success.
#   3) secrets     - nameref (optional); array of podman secret names passed through to
#         ignition_merge_compile_entry() (and from there to ignition_gen()) for mounting
#         secrets inside the butane container.
# Outputs:
#   Logs the merge entry count, per-entry progress, and the final config size;
#   log_error messages to the log on failure.
# Returns:
#   1 if butane_path does not exist, or any step of the merge/compile pipeline fails;
#   0 otherwise.
ignition::gen_config_merge_inlines() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 2 "$@" || return 1
  local -r butane_path="$1"
  local -n out="$2"
  local -r secrets="${3:-"${__empty_array_ref}"}"

  if [[ ! -f "${butane_path}" ]]; then
    log_error "${ERROR_FILE_NOT_FOUND}: ${butane_path}"
    return 1
  fi

  # Parse the top-level butane YAML to compact JSON, stripping all comments.
  local config_json
  if ! config_json="$(yq -o json -I 0 '... comments="" | . | select(. != null)' \
    "${butane_path}")"; then
    log_error "failed to load config json from: ${butane_path}"
    return 1
  fi

  # jq path array addressing .ignition.config.merge[].
  local -r merge_jq_path='["ignition", "config", "merge"]'

  local -i entry_count
  if ! entry_count="$(jq --argjson merge_jq_path "${merge_jq_path}" \
    'getpath($merge_jq_path) | length' \
    <<< "${config_json}")"; then
    log_error "failed to get entry count."
    return 1
  fi
  log_debug "merge entry count: ${entry_count}"

  # jq function shared by every per-entry jq call below.
  # bounds_check(expr) guards against an out-of-range $idx before evaluating expr.
  # shellcheck disable=SC2016
  local -r _jq_bounds_check='def bounds_check(expr):
        if (getpath($merge_jq_path) | length) > $idx then expr
        else "Index \($idx) out of bounds" | halt_error(1) end;'

  local -i idx
  local butane_file_path ignition_json verification_hash
  for ((idx = 0; idx < entry_count; idx++)); do
    log_debug "Processing merge entry [${idx}]"

    if ! butane_file_path="$(ignition::merge_read_inline_path "${config_json}" \
      "${merge_jq_path}" "${idx}" "${_jq_bounds_check}")"; then
      log_error "failed to read inline path at merge index ${idx}"
      return 1
    fi
    log_debug "$(declare -p butane_file_path)"

    if ! ignition::merge_compile_entry "${butane_file_path}" \
      ignition_json \
      verification_hash \
      "${secrets}"; then
      log_error "failed to compile ignition merge inline entry."
      return 1
    fi

    if ! config_json="$(ignition::merge_write_entry "${config_json}" \
      "${merge_jq_path}" \
      "${idx}" \
      "${_jq_bounds_check}" \
      "${ignition_json}" \
      "${verification_hash}")"; then
      log_error "failed to update inline entry at merge index ${idx}"
      return 1
    fi
  done

  log_info "Generating final main ignition config..."
  local ignition_out
  if ! ignition_out="$(ignition::butane -m "$(dirname "${butane_path}")" \
    -- \
    --strict \
    "--files-dir=files" \
    <<< "${config_json}")"; then
    log_error "failed to compile merged butane config to ignition JSON"
    return 1
  fi
  log_info "Config ok"
  log_info "Config size: $(wc -c <<< "${ignition_out}") bytes"

  # shellcheck disable=SC2034
  out="${ignition_out}"
}

if [[ "${__BASHKIT_LIB_CORE_CONTRACT_UTILS_SOURCED:-}" != "true" ]]; then
  # shellcheck source=../core/contract-utils.sh
  . "${BASH_SOURCE[0]%/*}/../core/contract-utils.sh"
fi

if [[ "${__BASHKIT_LIB_IGNITION_BUTANE_SOURCED:-}" != "true" ]]; then
  # shellcheck source=butane.sh
  . "${BASH_SOURCE[0]%/*}/butane.sh"
fi

if [[ "${__BASHKIT_LIB_CORE_SHA512SUM_UTILS_SOURCED:-}" != "true" ]]; then
  # shellcheck source=../core/sha512sum-utils.sh
  . "${BASH_SOURCE[0]%/*}/../core/sha512sum-utils.sh"
fi
