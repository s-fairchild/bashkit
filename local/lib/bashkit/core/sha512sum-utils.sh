# shellcheck shell=bash
#
# Wraps the real `sha512sum` coreutils binary with stdin-driven generate/check helpers.

readonly __BASHKIT_LIB_CORE_SHA512SUM_UTILS_SOURCED="true"

# core::sha512sum(...)
#
# Shadows the coreutils `sha512sum` binary so callers in this tree always go through one
# call site; delegates every argument straight through.
#
# Arguments:
#   $@ - passed verbatim to `command sha512sum`.
# Outputs:
#   Whatever `sha512sum` writes to stdout/stderr.
# Returns:
#   `sha512sum`'s exit status.
core::sha512sum() {
  command sha512sum "$@"
}

# core::sha512sum_gen_stdin()
#
# Generates a sha512 checksum for stdin.
#
# Outputs:
#   Writes `sha512sum -`'s output to stdout.
# Returns:
#   1 if stdin is a TTY (no piped/redirected input).
core::sha512sum_gen_stdin() {
  log_debug "Starting ${FUNCNAME[0]}()"

  [[ ! -t 0 ]] || { core::fail "stdin cannot be null." || return; }

  # PIPESTATUS is checked by core::require_pipestatus below.
  # shellcheck disable=SC2312
  cat | core::sha512sum -
  core::require_pipestatus "${PIPESTATUS[@]}" || return
}

# core::sha512sum_check_stdin()
#
# Checks a sha512sum-formatted checksum line read from stdin against the referenced file(s).
#
# Outputs:
#   Whatever `sha512sum --check` writes to stdout/stderr.
# Returns:
#   1 if stdin is a TTY; otherwise `sha512sum --check`'s exit status.
core::sha512sum_check_stdin() {
  log_debug "Starting ${FUNCNAME[0]}()"

  [[ ! -t 0 ]] || { core::fail "stdin cannot be null." || return; }

  local -ar sha512sum_check_options=(
    "--check"
    "--strict"
    "--warn"
  )
  log_debug "$(declare -p sha512sum_check_options)"

  core::sha512sum "${sha512sum_check_options[@]}" -
}

# core::sha512sum_gen(input)
#
# Generates a sha512 checksum for $1, or stdin when $1 is omitted.
#
# Arguments:
#   *) input - string (optional); data to hash. Read from stdin when omitted.
# Outputs:
#   Writes `sha512sum_gen_stdin`'s output to stdout.
# Returns:
#   1 if neither $1 nor piped/redirected stdin is provided.
core::sha512sum_gen() {
  log_debug "Starting ${FUNCNAME[0]}()"

  local input
  if (( $# )); then
    log_debug "input from \$1"
    input="$*"
  elif [[ ! -t 0 ]]; then
    log_debug "input from stdin."
    input="$(cat)"
  else
    core::fail "input cannot be null." || return
  fi
  readonly input

  core::sha512sum_gen_stdin <<< "${input}"
}

# core::sha512sum_check(input)
#
# Checks a sha512sum-formatted checksum line, from $1 or stdin, against the referenced file(s).
#
# Arguments:
#   *) input - string (optional); a checksum line. Read from stdin when omitted.
# Outputs:
#   Whatever `sha512sum_check_stdin` writes to stdout/stderr.
# Returns:
#   1 if neither $1 nor piped/redirected stdin is provided.
core::sha512sum_check() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  local input
  if (( $# )); then
    input="$*"
  elif [[ ! -t 0 ]]; then
    input="$(cat)"
  else
    core::fail "input cannot be null." || return
  fi
  readonly input

  [[ -n "${input}" ]] || { core::fail "input cannot be empty string." || return; }

  core::sha512sum_check_stdin <<< "${input}"
}

# core::checksum_parse_hash(input)
#
# Extracts the hash value (first whitespace-delimited field) from a checksum-tool line, e.g.
# "<hex>  -" from `sha512sum`'s output.
#
# Arguments:
#   *) input - string; a checksum-tool output line.
# Outputs:
#   Writes the parsed hash value to stdout.
# Returns:
#   1 if the parsed value is empty.
core::checksum_parse_hash() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  local input
  if (( $# )); then
    input="$*"
  elif [[ ! -t 0 ]]; then
    input="$(cat)"
  else
    core::fail "input cannot be null." || return
  fi
  readonly input

  [[ -n "${input}" ]] || { core::fail "input cannot be empty string." || return; }

  local output
  output="$(cut -d ' ' -f 1 <<< "${input}")"
  readonly output
  [[ -n "${output}" ]] || { core::fail "failed to parse checksum value." || return; }

  printf "%s" "${output}"
}

# core::checksum_format_verification_hash_sha512(input)
#
# Formats a sha512 checksum-tool line (or a raw hex digest passed as $1) as an Ignition
# "sha512-<hex>" verification.hash value.
#
# Arguments:
#   *) input - string (optional); a raw checksum-tool output line/digest. When omitted, read
#      from stdin.
# Outputs:
#   Writes the "sha512-<hex>" formatted hash to stdout.
# Returns:
#   Non-zero if neither $1 nor stdin provided input.
core::checksum_format_verification_hash_sha512() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  local input
  if (( $# )); then
    input="$*"
  elif [[ ! -t 0 ]]; then
    input="$(cat)"
  else
    core::fail "input cannot be null." || return
  fi
  readonly input

  [[ -n "${input}" ]] || { core::fail "input cannot be empty string." || return; }

  local hash
  hash="$(core::checksum_parse_hash "${input}")" || return
  printf "sha512-%s" "${hash}"
}

if [[ "${__BASHKIT_CORE_CONTRACT_UTILS_SOURCED:-}" != "true" ]]; then
  # shellcheck source=../core/contract-utils.sh
  . "${BASH_SOURCE[0]%/*}/../core/contract-utils.sh"
fi
