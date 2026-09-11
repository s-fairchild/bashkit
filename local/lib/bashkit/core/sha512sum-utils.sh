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

  if [[ -t 0 ]]; then
    log_error "${FUNCNAME[0]}(): stdin cannot be null."
    return 1
  fi

  cat | core::sha512sum -
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

  if [[ -t 0 ]]; then
    log_error "${FUNCNAME[0]}(): stdin cannot be null."
    return 1
  fi

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
#   1) input - string (optional); data to hash. Read from stdin when omitted.
# Outputs:
#   Writes `sha512sum_gen_stdin`'s output to stdout.
# Returns:
#   1 if neither $1 nor piped/redirected stdin is provided.
core::sha512sum_gen() {
  log_debug "Starting ${FUNCNAME[0]}()"

  if (( $# )); then
    local -r input="$1"
  elif [[ ! -t 0 ]]; then
    local -r input="$(cat)"
  else
    log_error "${FUNCNAME[0]}(): stdin AND \$1 positional argument cannot be null."
    return 1
  fi

  core::sha512sum_gen_stdin <<< "${input}"
}

# core::sha512sum_check(input)
#
# Checks a sha512sum-formatted checksum line, from $1 or stdin, against the referenced file(s).
#
# Arguments:
#   1) input - string (optional); a checksum line. Read from stdin when omitted.
# Outputs:
#   Whatever `sha512sum_check_stdin` writes to stdout/stderr.
# Returns:
#   1 if neither $1 nor piped/redirected stdin is provided.
core::sha512sum_check() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  if (( $# )); then
    local -r input="${1:-}"
  elif [[ ! -t 0 ]]; then
    local -r input="$(cat)"
  else
    log_error "${FUNCNAME[0]}(): stdin AND \$1 positional argument cannot be null."
    return 1
  fi

  if [[ -z "${input}" ]]; then
    log_error "\$1 and/or stdin cannot be empty string."
    return 1
  fi

  core::sha512sum_check_stdin <<< "${input}"
}

# core::checksum_parse_hash(input)
#
# Extracts the hash value (first whitespace-delimited field) from a checksum-tool line, e.g.
# "<hex>  -" from `sha512sum`'s output.
#
# Arguments:
#   1) input - string; a checksum-tool output line.
# Outputs:
#   Writes the parsed hash value to stdout.
# Returns:
#   1 if the parsed value is empty.
core::checksum_parse_hash() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  if (( $# )); then
    local -r input="${1:-}"
  elif [[ ! -t 0 ]]; then
    local -r input="$(cat)"
  else
    log_error "${FUNCNAME[0]}(): stdin AND \$1 positional argument cannot be null."
    return 1
  fi

  if [[ -z "${input}" ]]; then
    log_error "\$1 and/or stdin cannot be empty string."
    return 1
  fi

  local -r output="$(cut -d ' ' -f 1 <<< "${input}")"
  if [[ -z "${output}" ]]; then
    log_error "failed to parse checksum value."
    return 1
  fi

  printf "%s" "${output}"
}

# core::checksum_format_verification_hash_sha512(input)
#
# Formats a sha512 checksum-tool line (or a raw hex digest passed as $1) as an Ignition
# "sha512-<hex>" verification.hash value.
#
# Arguments:
#   1) input - string (optional); a raw checksum-tool output line/digest. When omitted, read
#      from stdin.
# Outputs:
#   Writes the "sha512-<hex>" formatted hash to stdout.
# Returns:
#   Non-zero if neither stdin nor $1 provided input.
core::checksum_format_verification_hash_sha512() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  if [[ ! -t 0 ]]; then
    local -r input="$(cat)"
  elif (( $# )); then
    local -r input="$1"
  else
    log_error "${FUNCNAME[0]}(): stdin AND \$1 positional argument cannot be null."
    return 1
  fi

  if [[ -z "${input}" ]]; then
    log_error "\$1 and/or stdin cannot be empty string."
    return 1
  fi

  printf "sha512-%s" "$(core::checksum_parse_hash "${input}")"
}

if ! declare -f init_logger >/dev/null 2>&1; then
  # logging.sh should already be sourced by now.
  # This is primarily present to provide shellcheck function definitions.
  #
  # shellcheck source=../../../../../bash-logger/logging.sh
  . "${BASH_SOURCE[0]%/*}/../../../../../bash-logger/logging.sh"

  init_logger --name "$(basename "$0")"
fi
