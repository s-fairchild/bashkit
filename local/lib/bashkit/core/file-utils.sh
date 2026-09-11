# shellcheck shell=bash
#
# File-reading helpers: read a file (or stdin) into memory, with or without
# preserving trailing newlines, and parse a file's extension.

[[ "${XTRACE:-0}" -eq 1 ]] && set -x

readonly __BASHKIT_LIB_CORE_FILE_UTILS_SOURCED="true"
readonly __bashkit_core_file_utils_error_file_not_found="a file must be provided to read into memory."

# core::file_read_builtin([file])
#
# Reads a file into memory using the `$(<file)` builtin, or reads stdin if
# it is not a terminal. Strips trailing newlines (see
# core::file_read_preserve_newlines for a variant that keeps them).
#
# Globals:
#   __bashkit_core_file_utils_error_file_not_found
# Arguments:
#   $1   Optional path to the file to read. Read from stdin if omitted and
#        stdin is not a terminal.
# Outputs:
#   The file's contents (trailing newlines stripped) on stdout.
# Returns:
#   1 if no file/stdin was provided, or if the read result is empty.
core::file_read_builtin() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  local input
  if [[ -t 0 ]]; then
    input="$(cat)"
  elif (( $# )); then
    input="$*"
  else
    log_error "${ERROR_ARG_REQUIRED}: ${__bashkit_core_file_utils_error_file_not_found}"
    return 1
  fi
  log_sensitive "$(declare -p input)"

  local output
  output="$(<"${input}")"
  log_sensitive "$(declare -p output)"

  if [[ -z "${output}" ]]; then
    log_error "failed to read file ${1} into memory."
    return 1
  fi

  printf "%s" "${output}"
}

# core::file_read_preserve_newlines([file])
#
# Reads a file into memory, preserving trailing newlines (unlike
# core::file_read_builtin).
#
# Globals:
#   __bashkit_core_file_utils_error_file_not_found
# Arguments:
#   $1   Optional path to the file to read. Read from stdin if omitted and
#        stdin is not a terminal.
# Outputs:
#   The file's contents (newlines preserved) on stdout.
# Returns:
#   1 if no file/stdin was provided, or if the read result is empty.
core::file_read_preserve_newlines() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  local input
  if [[ -t 0 ]]; then
    input="$(cat)"
  elif (( $# )); then
    input="$*"
  else
    log_error "${ERROR_ARG_REQUIRED}: ${__bashkit_core_file_utils_error_file_not_found}"
    return 1
  fi
  log_sensitive "$(declare -p input)"

  local output
  IFS= read -r -d '' output < "${input}" || true
  log_sensitive "$(declare -p output)"

  if [[ -z "${output}" ]]; then
    log_error "failed to read file ${1} into memory."
    return 1
  fi

  printf "%s" "${output}"
}

# core::file_parse_extension([file])
#
# Parses the extension off a file path (the substring after the final `.`
# in its basename).
#
# Globals:
#   __bashkit_core_file_utils_error_file_not_found
# Arguments:
#   $1   Optional file path. Read from stdin if omitted and stdin is not a
#        terminal.
# Outputs:
#   The parsed extension on stdout.
# Returns:
#   1 if no file/stdin was provided, or if no extension could be parsed.
core::file_parse_extension() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  local input
  if [[ -t 0 ]]; then
    input="$(cat)"
  elif (( $# )); then
    input="$*"
  else
    log_error "${ERROR_ARG_REQUIRED}: ${__bashkit_core_file_utils_error_file_not_found}"
    return 1
  fi
  # DEBUG-level logging should be fine as this *should* only be a file
  # extension, but log_sensitive is used here just in case sensitive data
  # ends up here by accident.
  log_sensitive "$(declare -p input)"

  local output
  output="$(basename "${input}")"
  log_sensitive "$(declare -p output)"
  output="${output##*.}"
  log_sensitive "$(declare -p output)"

  if [[ -z "${output}" ]]; then
    log_error "failed to parse checksum value."
    return 1
  fi

  printf "%s" "${output}"
}

if ! declare -f init_logger >/dev/null 2>&1; then
  # logging.sh should already be sourced by now.
  # This is primarily present to provide shellcheck function definitions.
  #
  # shellcheck source=../../../../../bash-logger/logging.sh
  . "${BASH_SOURCE[0]%/*}/../../../../../bash-logger/logging.sh"

  init_logger --name "$(basename "$0")"
fi
