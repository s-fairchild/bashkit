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
core::is_boolean() {
  core::require_operands 1 "$@" || return
  local bool="$1"
  readonly bool="${bool,,}"

  local boolean_values="${__BASHKIT_CORE_BOOLEAN_TRUE}|${__BASHKIT_CORE_BOOLEAN_FALSE}"
  boolean_values+="|${__BASHKIT_CORE_BOOLEAN_ON}|${__BASHKIT_CORE_BOOLEAN_OFF}"
  boolean_values+="|${__BASHKIT_CORE_BOOLEAN_YES}|${__BASHKIT_CORE_BOOLEAN_NO}"
  readonly boolean_values

  if ! [[ "${bool}" =~ ^(${boolean_values})$ ]]; then
    log_error "${1} must match regex: ${boolean_values}"
    core::print_stack_trace
    return 1
  fi
}

if [[ "${__BASHKIT_CORE_CONTRACT_UTILS_SOURCED:-}" != "true" ]]; then
  # shellcheck source=contract-utils.sh
  . "${BASH_SOURCE[0]%/*}/contract-utils.sh"
fi
