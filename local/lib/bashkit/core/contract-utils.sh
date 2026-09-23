# shellcheck shell=bash
#
# Argument/operand validation and getopts helpers shared across bashkit and
# its consumers: core::fail, core::require_operands, core::is_option_arg_dup,
# and core::with_xtrace_suppressed. core::print_stack_trace lives in
# logger-utils.sh, which this file sources, so it works before the logger is
# loaded.

[[ "${XTRACE:-0}" -eq 1 ]] && set -x

readonly __BASHKIT_CORE_CONTRACT_UTILS_SOURCED="true"

readonly __BASHKIT_CORE_BOOLEAN_TRUE="true"
readonly __BASHKIT_CORE_BOOLEAN_FALSE="false"
readonly __BASHKIT_CORE_BOOLEAN_ON="on"
readonly __BASHKIT_CORE_BOOLEAN_OFF="off"
readonly __BASHKIT_CORE_BOOLEAN_YES="yes"
readonly __BASHKIT_CORE_BOOLEAN_NO="no"

readonly __BASHKIT_CORE_ERROR_OPTION_OPERAND_MISSING="value must be provided"
readonly __BASHKIT_CORE_ERROR_OPTION_UNKNOWN="option is unknown"

core::fail() {
  log_error "${FUNCNAME[1]}(): $*"
  core::print_stack_trace
  return 1
}

# core::require_operands(count "$@")
#
# Validates that the caller's first <count> positional parameters are set
# (present, even if empty -- matches this repo's `${N?...}` unset-only
# convention, not `-z`). Logs "$N <ERROR_OPERAND_REQUIRED>" for the first
# missing one and returns 1.
#
# `return` here only unwinds core::require_operands itself, not its caller --
# the caller must check the exit status and return on its own behalf. Use a
# bare `|| return` (not `|| return 1`) so the caller propagates whatever
# status core::fail produced rather than hardcoding it:
#
#   my_fn() {
#     core::require_operands 3 "$@" || return
#     local -r a="$1" b="$2" c="$3"
#     ...
#   }
#
# Globals:
#   ERROR_OPERAND_REQUIRED
# Arguments:
#   $1   Number of leading positional parameters that must be set.
#   $@   The caller's own "$@" (count included), forwarded so the check can
#        inspect it.
# Outputs:
#   An error and stack trace on the first missing operand.
# Returns:
#   1 if any of the first <count> operands is unset; 0 otherwise.
core::require_operands() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  local -ri count="$1"; shift
  local -i i
  for (( i = 1; i <= count; i++ )); do
    [[ -v "${i}" ]] || { core::fail "\$${i} operand is required." || return; }
  done
}

# core::require_pipestatus("${PIPESTATUS[@]}")
#
# Validates that every stage of the caller's most recent pipeline exited 0.
# Logs the first non-zero stage (by PIPESTATUS index) along with the full
# status list, plus a stack trace, and returns 1.
#
# PIPESTATUS is overwritten by every command, so this must be the very next
# command after the pipeline, with the array expanded as its arguments
# (the expansion happens before this function runs, so it isn't clobbered):
#
#   my_fn() {
#     producer | consumer
#     core::require_pipestatus "${PIPESTATUS[@]}" || return
#   }
#
# Don't append `|| ...` to the pipeline itself; that would run a command
# and replace PIPESTATUS before it can be checked.
#
# Globals:
#   None.
# Arguments:
#   $@   The caller's "${PIPESTATUS[@]}", one exit status per stage.
# Outputs:
#   An error and stack trace on the first non-zero stage.
# Returns:
#   1 if any stage exited non-zero; 0 otherwise.
core::require_pipestatus() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return

  local -i i=0
  local status
  for status in "$@"; do
    (( status == 0 )) || {
      core::fail "pipeline stage PIPESTATUS[${i}] exited ${status}: PIPESTATUS=($*)" \
        || return
    }
    (( ++i ))
  done
}

# core::require_nameref(name [expected_type])
#
# Validates a variable name the caller is about to bind with `local -n`.
# Rejects invalid identifiers and, when <expected_type> is given ("a", "A",
# or "-" for scalar), requires the target to already be declared with that
# type. Cannot detect shadowing by the caller's own locals -- prefix
# nameref/local names in ref-taking functions to avoid that.
core::require_nameref() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  core::require_operands 1 "$@" || return
  local -r __crn_name="$1"
  local -r __crn_want="${2:-}"

  core::is_valid_var_name "${__crn_name}" || {
    core::fail "'${__crn_name}' is not a valid variable name." || return
  } 
  [[ -z "${__crn_want}" ]] && return 0

  local __crn_decl
  __crn_decl="$(declare -p "${__crn_name}" 2>/dev/null)" || {
    core::fail "'${__crn_name}' is not declared." || return
  }
  [[ "${__crn_decl}" == "declare -"*"${__crn_want}"* ]] || {
    core::fail "'${__crn_name}' is not of type -${__crn_want}." || return
  }
}

core::is_nameref_valid() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  core::require_operands 1 "$@" || return
  local -r __crn_name="${1:-}"

  [[ -R "${__crn_name}" ]] || {
    core::fail "'${__crn_name}' is not a valid nameref." || return
  }
}

# core::is_option_arg_dup(opt current_value)
#
# Rejects a repeated single-value getopts flag. Call it from a
# `case "$opt" in ...)` arm *before* assigning `OPTARG`, passing the target
# variable's current (pre-assignment) value as <current_value> -- a
# non-empty value there means the flag was already seen once. Logs
# "-<opt> <current_value> <ERROR_OPTION_ARG_DUP>" and returns 1 if so;
# no-ops otherwise.
#
# Globals:
#   ERROR_OPTION_ARG_DUP
# Arguments:
#   $1   The option letter/flag being parsed.
#   $2   The target variable's current value, prior to this OPTARG
#        assignment.
# Outputs:
#   An error if the flag is a duplicate.
# Returns:
#   1 if the flag is a duplicate; 0 otherwise.
core::is_option_arg_dup() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 2 "$@" || return
  local -r opt="$1"
  local -r opt_arg="$2"

  if [[ -n "${opt_arg}" ]]; then
    log_error "-${opt} ${opt_arg} ${ERROR_OPTION_ARG_DUP}"
    core::print_stack_trace
    return 1
  fi
}

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

# core::with_xtrace_suppressed(save state_var)
# core::with_xtrace_suppressed(restore state_var)
#
# save:    records whether xtrace (`set -x`) is currently active into
#          <state_var> (1 if active, 0 if not), then disables it. Call this
#          before running any command whose expanded arguments must not be
#          echoed -- including a command that only *tests* a value that
#          isn't known to be sensitive yet, since it's the trace line
#          itself that leaks, not the command's outcome.
# restore: re-enables xtrace if <state_var> recorded it as having been
#          active when saved. No-op otherwise. Idempotent, so it's safe to
#          call more than once against the same <state_var>.
#
# Globals:
#   ERROR_OPTION_UNKNOWN
# Arguments:
#   $1   Mode: "save" or "restore".
#   $2   Name of the caller's state variable (passed by reference).
# Outputs:
#   None.
# Returns:
#   Always 0 for "save"/"restore"; returns 1 on an unknown mode.
core::with_xtrace_suppressed() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 2 "$@" || return
  local -r mode="$1"
  local -n state="$2"

  case "${mode}" in
    save)
      case $- in
        *x*) state=1 ;;
        *)   state=0 ;;
      esac
      set +x
      ;;
    restore)
      # if/fi (not `&&`) so this always returns 0: under this repo's
      # errexit + ERR trap, a bare `(( state )) && set -x` would abort the
      # caller whenever state is 0, since the function's own return status
      # is inherited from its last-run command.
      if (( state )); then
        set -x
      fi
      ;;
    *)
      core::fail "${ERROR_OPTION_UNKNOWN}: ${mode}" || return
      ;;
  esac
}

core::is_valid_var_name() {
  [[ $1 =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

if [[ "${__BASHKIT_LIB_CORE_LOGGER_UTILS_SOURCED:-}" != "true" ]]; then
  # shellcheck source=logger-utils.sh
  . "${BASH_SOURCE[0]%/*}/logger-utils.sh"
fi

core::logger_init --name "$(basename "$0")"
