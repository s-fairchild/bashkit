# shellcheck shell=bash
#
# File-reading helpers: read a file (or stdin) into memory, with or without
# preserving trailing newlines, and parse a file's extension.

[[ "${XTRACE:-0}" -eq 1 ]] && set -x

readonly __BASHKIT_LIB_CORE_FILE_UTILS_SOURCED="true"

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
  log_sensitive "$(declare -p input)"
  [[ -n "${input}" ]] || { core::fail "input cannot be empty string." || return; }

  local output
  output="$(<"${input}")"
  readonly output
  log_sensitive "$(declare -p output)"
  [[ -n "${output:-}" ]] || { core::fail "failed to parse input file ${input} into output" || return; }

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
  if (( $# )); then
    input="$*"
  elif [[ ! -t 0 ]]; then
    input="$(cat)"
  else
    core::fail "input cannot be null." || return
  fi
  readonly input
  log_sensitive "$(declare -p input)"
  [[ -n "${input}" ]] || { core::fail "input cannot be empty string" || return; }

  local output
  IFS= read -r -d '' output < "${input}" || true
  readonly output
  log_sensitive "$(declare -p output)"
  [[ -n "${output:-}" ]] || { core::fail "failed to parse input file ${input} into output" || return; }

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
  if (( $# )); then
    input="$*"
  elif [[ ! -t 0 ]]; then
    input="$(cat)"
  else
    core::fail "input cannot be null." || return
  fi
  readonly input
  # DEBUG-level logging should be fine as this *should* only be a file
  # extension, but log_sensitive is used here just in case sensitive data
  # ends up here by accident.
  log_sensitive "$(declare -p input)"
  [[ -n "${input}" ]] || { core::fail "input cannot be empty string" || return; }

  local output
  output="$(basename "${input}")"
  log_sensitive "$(declare -p output)"
  output="${output##*.}"
  readonly output
  log_sensitive "$(declare -p output)"

  [[ -n "${output}" ]] || {
    core::fail "failed to parse output. output is empty string." \
      || return
  }

  printf "%s" "${output}"
}

if [[ "${__BASHKIT_LIB_CORE_CONTRACT_UTILS_SOURCED:-}" != "true" ]]; then
  # shellcheck source=../core/contract-utils.sh
  . "${BASH_SOURCE[0]%/*}/../core/contract-utils.sh"
fi
