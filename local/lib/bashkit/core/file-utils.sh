# shellcheck shell=bash
#
# File-reading helpers: read a file (or stdin) into memory, with or without
# preserving trailing newlines, and parse a file's extension.

declare -r __vendor_bashkit_lib_file_utils_sourced="true"
declare -r __error_no_file="a file must be provided to read into memory."

# read_file_builtin([file])
#
# Reads a file into memory using the `$(<file)` builtin, or reads stdin if
# it is not a terminal. Strips trailing newlines (see
# read_file_preserve_newlines for a variant that keeps them).
#
# Globals:
#   __error_no_file
# Arguments:
#   $1   Optional path to the file to read. Read from stdin if omitted and
#        stdin is not a terminal.
# Outputs:
#   The file's contents (trailing newlines stripped) on stdout.
# Returns:
#   1 if no file/stdin was provided, or if the read result is empty.
read_file_builtin() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  local input
  if [[ -t 0 ]]; then
    input="$(cat)"
  elif (( $# )); then
    input="$*"
  else
    error "${ERROR_ARG_REQUIRED}: ${__error_no_file}"
    return 1
  fi
  log_sensitive "$(declare -p input)"

  local output
  output="$(<"${input}")"
  log_sensitive "$(declare -p output)"

  if [[ -z "${output}" ]]; then
    error "failed to read file ${1} into memory."
    return 1
  fi

  printf "%s" "${output}"
}

# read_file_preserve_newlines([file])
#
# Reads a file into memory, preserving trailing newlines (unlike
# read_file_builtin).
#
# Globals:
#   __error_no_file
# Arguments:
#   $1   Optional path to the file to read. Read from stdin if omitted and
#        stdin is not a terminal.
# Outputs:
#   The file's contents (newlines preserved) on stdout.
# Returns:
#   1 if no file/stdin was provided, or if the read result is empty.
read_file_preserve_newlines() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  local input
  if [[ -t 0 ]]; then
    input="$(cat)"
  elif (( $# )); then
    input="$*"
  else
    error "${ERROR_ARG_REQUIRED}: ${__error_no_file}"
    return 1
  fi
  log_sensitive "$(declare -p input)"

  local output
  IFS= read -r -d '' output < "${input}" || true
  log_sensitive "$(declare -p output)"

  if [[ -z "${output}" ]]; then
    error "failed to read file ${1} into memory."
    return 1
  fi

  printf "%s" "${output}"
}

# parse_file_extension([file])
#
# Parses the extension off a file path (the substring after the final `.`
# in its basename).
#
# Globals:
#   __error_no_file
# Arguments:
#   $1   Optional file path. Read from stdin if omitted and stdin is not a
#        terminal.
# Outputs:
#   The parsed extension on stdout.
# Returns:
#   1 if no file/stdin was provided, or if no extension could be parsed.
parse_file_extension() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  local input
  if [[ -t 0 ]]; then
    input="$(cat)"
  elif (( $# )); then
    input="$*"
  else
    error "${ERROR_ARG_REQUIRED}: ${__error_no_file}"
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
    error "failed to parse checksum value."
    return 1
  fi

  printf "%s" "${output}"
}

if [[ "${__bash_logger_adapter_sourced:-}" != "true" ]]; then
  declare __bash_logger_adapter_path="${BASH_SOURCE[0]%/*}/../../../../bash-logger-adapter/adapter.sh"
  [[ -f "${__bash_logger_adapter_path}" ]] || { printf '%s\n' "failed to find file: ${__bash_logger_adapter_path}" >&2; exit 1; }
  # shellcheck source=../../../../bash-logger-adapter/adapter.sh
  . "${__bash_logger_adapter_path}"
  unset __bash_logger_adapter_path
fi
