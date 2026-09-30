# shellcheck shell=bash
#
# Recognized boolean spellings (the __BASHKIT_CORE_BOOLEAN_* constants) and
# core::is_boolean, which validates a string against them.

[[ "${XTRACE:-0}" -eq 1 ]] && set -x

readonly __BASHKIT_LIB_CORE_BOOLEAN_UTILS_SOURCED="true"

readonly __BASHKIT_CORE_BOOLEAN_TRUE="true"
readonly __BASHKIT_CORE_BOOLEAN_FALSE="false"
readonly __BASHKIT_CORE_BOOLEAN_ON="on"
readonly __BASHKIT_CORE_BOOLEAN_OFF="off"
readonly __BASHKIT_CORE_BOOLEAN_YES="yes"
readonly __BASHKIT_CORE_BOOLEAN_NO="no"
declare -ir __BASHKIT_CORE_BOOLEAN_TRUE_INT=1
declare -ir __BASHKIT_CORE_BOOLEAN_FALSE_INT=0

# core::is_boolean(value)
#
# Validates that a string is a recognized boolean spelling (case-insensitive):
# true/false, on/off, or yes/no. Logs an error and a stack trace if not.
#
# Globals:
#   __BASHKIT_CORE_BOOLEAN_TRUE, __BASHKIT_CORE_BOOLEAN_FALSE, __BASHKIT_CORE_BOOLEAN_ON, __BASHKIT_CORE_BOOLEAN_OFF, __BASHKIT_CORE_BOOLEAN_YES, __BASHKIT_CORE_BOOLEAN_NO
# Arguments:
#   $1   String to validate.
# Outputs:
#   An error and stack trace if the value doesn't match a recognized spelling.
# Returns:
#   1 if the value is not a recognized boolean spelling; 0 otherwise.
core::_bool_is_string() {
  local -r bool="${1:-}"

  [[ -n "${bool}" ]] || {
    echo "${FUNCNAME[0]}(): bool=\$1 cannot be empty." >&2
    declare -f core::print_stack_trace >/dev/null 2>&1 \
      && core::print_stack_trace
    return 5
  }

  local boolean_values="${__BASHKIT_CORE_BOOLEAN_TRUE}"
  boolean_values+="|${__BASHKIT_CORE_BOOLEAN_FALSE}"
  boolean_values+="|${__BASHKIT_CORE_BOOLEAN_ON}"
  boolean_values+="|${__BASHKIT_CORE_BOOLEAN_OFF}"
  boolean_values+="|${__BASHKIT_CORE_BOOLEAN_YES}"
  boolean_values+="|${__BASHKIT_CORE_BOOLEAN_NO}"
  readonly boolean_values
  declare -f log_debug >/dev/null 2>&1 \
    && log_debug "$(declare -p boolean_values)"

  [[ "${bool}" =~ ^(${boolean_values})$ ]]
}

core::_bool_is_int() {
  local -r bool="${1}"

  (( bool == __BASHKIT_CORE_BOOLEAN_TRUE_INT )) || \
  (( bool == __BASHKIT_CORE_BOOLEAN_FALSE_INT ))
}

# TODO setup trap for exit code 5 to fail
# Reasoning: core::bool_is_true returns 0 if the boolean is valid and true
# returns 1 if boolean is valid and false
# returns 5 if boolean is invalid, any other error
# exit code 5 must be trapped and acted on to catch errors.
core::bool_is_true() {
  local bool="${1}"
  readonly bool

  local regex_bool_true="${__BASHKIT_CORE_BOOLEAN_TRUE}"
  regex_bool_true+="|${__BASHKIT_CORE_BOOLEAN_YES}"
  regex_bool_true+="|${__BASHKIT_CORE_BOOLEAN_ON}"
  readonly regex_bool_true

  local regex_bool_false="${__BASHKIT_CORE_BOOLEAN_FALSE}"
  regex_bool_false+="|${__BASHKIT_CORE_BOOLEAN_NO}"
  regex_bool_false+="|${__BASHKIT_CORE_BOOLEAN_OFF}"
  readonly regex_bool_false

  # if core::_bool_is_int "${bool}"; then
    # return "${bool}"
  if core::_bool_is_string "${bool}"; then
    [[ "${bool}" =~ ^(${regex_bool_true})$ ]] || return 1
  else
    return 5
  fi
}
