# shellcheck shell=bash
#
# Recognized boolean spellings (the __BASHKIT_CORE_BOOLEAN_* constants) and
# the predicates that test a value against them, core::bool_is_valid and
# core::bool_is_true. Both accept true/false, yes/no, and on/off in any case,
# and the integers 1/0.
#
# core::logger_init calls core::bool_is_true before bash-logger is loaded, so
# nothing here may need the logging API. The only dependency is
# logger-utils.sh (core::logger_resolve, core::print_stack_trace), which
# imports this file in turn. `import` loads each file once, which ends the
# loop.

# logger-utils.sh sources this file, so this directive doesn't point back at
# it. ShellCheck doesn't recognize that cycle as recursion when it lints from
# another directory, and follows it 100 levels deep until it runs out of
# memory. logger-utils.sh is linted on its own.
#
# shellcheck source=/dev/null
. /dev/null
import core/logger-utils.sh

[[ -v __BASHKIT_CORE_BOOLEAN_TRUE ]] \
  || readonly __BASHKIT_CORE_BOOLEAN_TRUE="true"
[[ -v __BASHKIT_CORE_BOOLEAN_FALSE ]] \
  || readonly __BASHKIT_CORE_BOOLEAN_FALSE="false"
[[ -v __BASHKIT_CORE_BOOLEAN_ON ]] \
  || readonly __BASHKIT_CORE_BOOLEAN_ON="on"
[[ -v __BASHKIT_CORE_BOOLEAN_OFF ]] \
  || readonly __BASHKIT_CORE_BOOLEAN_OFF="off"
[[ -v __BASHKIT_CORE_BOOLEAN_YES ]] \
  || readonly __BASHKIT_CORE_BOOLEAN_YES="yes"
[[ -v __BASHKIT_CORE_BOOLEAN_NO ]] \
  || readonly __BASHKIT_CORE_BOOLEAN_NO="no"
[[ -v __BASHKIT_CORE_BOOLEAN_TRUE_INT ]] \
  || readonly __BASHKIT_CORE_BOOLEAN_TRUE_INT=1
[[ -v __BASHKIT_CORE_BOOLEAN_FALSE_INT ]] \
  || readonly __BASHKIT_CORE_BOOLEAN_FALSE_INT=0

# The status core::bool_is_true returns for a value that isn't a boolean.
[[ -v __BASHKIT_CORE_BOOLEAN_INVALID_STATUS ]] \
  || readonly __BASHKIT_CORE_BOOLEAN_INVALID_STATUS=5

# Anchored regexes for every spelling of true, and of false. Match them
# against a lowercased value.
if [[ ! -v __BASHKIT_CORE_BOOLEAN_TRUE_REGEX ]]; then
  printf -v __BASHKIT_CORE_BOOLEAN_TRUE_REGEX '^(%s|%s|%s|%s)$' \
    "${__BASHKIT_CORE_BOOLEAN_TRUE}" "${__BASHKIT_CORE_BOOLEAN_YES}" \
    "${__BASHKIT_CORE_BOOLEAN_ON}" "${__BASHKIT_CORE_BOOLEAN_TRUE_INT}"
  readonly __BASHKIT_CORE_BOOLEAN_TRUE_REGEX
fi
if [[ ! -v __BASHKIT_CORE_BOOLEAN_FALSE_REGEX ]]; then
  printf -v __BASHKIT_CORE_BOOLEAN_FALSE_REGEX '^(%s|%s|%s|%s)$' \
    "${__BASHKIT_CORE_BOOLEAN_FALSE}" "${__BASHKIT_CORE_BOOLEAN_NO}" \
    "${__BASHKIT_CORE_BOOLEAN_OFF}" "${__BASHKIT_CORE_BOOLEAN_FALSE_INT}"
  readonly __BASHKIT_CORE_BOOLEAN_FALSE_REGEX
fi

# core::bool_is_valid(value)
#
# Tests whether <value> is a recognized boolean: true/false, yes/no, or on/off
# in any case, or the integer 1 or 0. Nothing else counts, including an empty
# or missing value, `01`, or ` 1`. Prints nothing, so it can be used directly
# in `if` or `&&`.
#
# Globals:
#   __BASHKIT_CORE_BOOLEAN_TRUE_REGEX
#   __BASHKIT_CORE_BOOLEAN_FALSE_REGEX
# Arguments:
#   $1   The value to test.
# Outputs:
#   None.
# Returns:
#   0 if <value> is a recognized boolean; 1 otherwise.
core::bool_is_valid() {
  if declare -f log_debug >/dev/null 2>&1; then
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))" 1>&2
  fi

  local -r bool="${1:-}"

  [[ "${bool,,}" =~ ${__BASHKIT_CORE_BOOLEAN_TRUE_REGEX} \
    || "${bool,,}" =~ ${__BASHKIT_CORE_BOOLEAN_FALSE_REGEX} ]]
}

# core::bool_is_true(value)
#
# Tests whether <value> is true: true, yes, or on in any case, or the integer
# 1. false, no, off, and 0 are false. Any other value (see
# core::bool_is_valid) is an error: it is logged with a stack trace, and the
# status is __BASHKIT_CORE_BOOLEAN_INVALID_STATUS (5).
#
# In a plain `if` or `&&`, an invalid value acts like false once the error is
# logged. To treat it as a failure, check the status:
#
#   local -i status=0
#   core::bool_is_true "${value}" || status=$?
#   (( status != __BASHKIT_CORE_BOOLEAN_INVALID_STATUS )) || return 1
#
# or check the value with core::bool_is_valid first.
#
# Globals:
#   __BASHKIT_CORE_BOOLEAN_TRUE_REGEX
#   __BASHKIT_CORE_BOOLEAN_INVALID_STATUS
# Arguments:
#   $1   The value to test.
# Outputs:
#   An error and stack trace to stderr if <value> isn't a recognized boolean.
# Returns:
#   0 if <value> is true; 1 if it is false; 5 if it isn't a boolean.
core::bool_is_true() {
  core::_log_entry_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  local -r bool="${1:-}"

  if ! core::bool_is_valid "${bool}"; then
    local _log_entry_error
    _log_entry_error="$(core::logger_resolve error)"
    readonly _log_entry_error

    # log_error prints only its first operand, so build a single string.
    local msg
    printf -v msg \
      "%s(): '%s' is not a boolean. Expected %s/%s, %s/%s, %s/%s, or %d/%d." \
      "${FUNCNAME[0]}" \
      "${bool}" \
      "${__BASHKIT_CORE_BOOLEAN_TRUE}" \
      "${__BASHKIT_CORE_BOOLEAN_FALSE}" \
      "${__BASHKIT_CORE_BOOLEAN_YES}" \
      "${__BASHKIT_CORE_BOOLEAN_NO}" \
      "${__BASHKIT_CORE_BOOLEAN_ON}" \
      "${__BASHKIT_CORE_BOOLEAN_OFF}" \
      "${__BASHKIT_CORE_BOOLEAN_TRUE_INT}" \
      "${__BASHKIT_CORE_BOOLEAN_FALSE_INT}"
    readonly msg

    "${_log_entry_error}" "${msg}"
    core::print_stack_trace
    return "${__BASHKIT_CORE_BOOLEAN_INVALID_STATUS}"
  fi

  [[ "${bool,,}" =~ ${__BASHKIT_CORE_BOOLEAN_TRUE_REGEX} ]]
}
