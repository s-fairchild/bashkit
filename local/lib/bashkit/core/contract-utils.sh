# shellcheck shell=bash
#
# Argument/operand validation and getopts helpers shared across bashkit and
# its consumers: core::require_operands, core::is_option_arg_dup,
# core::with_xtrace_suppressed, and a stack-trace helper used when a
# contract check fails.

[[ "${XTRACE:-0}" -eq 1 ]] && set -x

readonly __BASHKIT_LIB_CORE_CONTRACT_UTILS_SOURCED="true"

readonly __BASHKIT_CORE_LIB_BOOLEAN_TRUE="true"
readonly __BASHKIT_CORE_LIB_BOOLEAN_FALSE="false"
readonly __BASHKIT_CORE_LIB_BOOLEAN_ON="on"
readonly __BASHKIT_CORE_LIB_BOOLEAN_OFF="off"
readonly __BASHKIT_CORE_LIB_BOOLEAN_YES="yes"
readonly __BASHKIT_CORE_LIB_BOOLEAN_NO="no"

readonly __BASHKIT_CORE_LIB_ERROR_OPTION_OPERAND_MISSING="value must be provided"
readonly __BASHKIT_CORE_LIB_ERROR_OPTION_UNKNOWN="option is unknown"

# core::require_operands(count "$@")
#
# Validates that the caller's first <count> positional parameters are set
# (present, even if empty -- matches this repo's `${N?...}` unset-only
# convention, not `-z`). Logs "$N <ERROR_OPERAND_REQUIRED>" for the first
# missing one and returns 1.
#
# `return` here only unwinds core::require_operands itself, not its caller --
# the caller must check the exit status and return on its own behalf:
#
#   my_fn() {
#     core::require_operands 3 "$@" || return 1
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
    if ! [[ -v "${i}" ]]; then
      log_error "\$${i} ${ERROR_OPERAND_REQUIRED}"
      core::print_stack_trace
      return 1
    fi
  done
}

# core::print_stack_trace()
#
# Logs the current bash call stack at LOG_LEVEL_ERROR, deepest frame first
# (starting at this function's caller), so a failed contract check --
# e.g. core::require_operands -- shows every calling function up to the
# entry-point script instead of just the one-line error. Safe to call from
# any function; each frame is logged as "at FUNCNAME (BASH_SOURCE:line)",
# where "line" is the line in that frame where it called into the
# next-deeper frame.
#
# Globals:
#   FUNCNAME, BASH_SOURCE, BASH_LINENO
# Arguments:
#   None.
# Outputs:
#   The call stack, one frame per line, at ERROR level.
# Returns:
#   Always 0.
core::print_stack_trace() {
  local -i i
  log_error "Stack trace (most recent call first):"
  for (( i = 1; i < ${#FUNCNAME[@]}; i++ )); do
    log_error "  at ${FUNCNAME[${i}]} (${BASH_SOURCE[${i}]}:${BASH_LINENO[$((i - 1))]})"
  done
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

  core::require_operands 2 "$@" || return 1
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
#   __BASHKIT_CORE_LIB_BOOLEAN_TRUE, __BASHKIT_CORE_LIB_BOOLEAN_FALSE, __BASHKIT_CORE_LIB_BOOLEAN_ON, __BASHKIT_CORE_LIB_BOOLEAN_OFF, __BASHKIT_CORE_LIB_BOOLEAN_YES, __BASHKIT_CORE_LIB_BOOLEAN_NO
# Arguments:
#   $1   String to validate.
# Outputs:
#   An error and stack trace if the value doesn't match a recognized spelling.
# Returns:
#   1 if the value is not a recognized boolean spelling; 0 otherwise.
core::is_boolean() {
  core::require_operands 1 "$@" || return 1
  local bool="$1"
  readonly bool="${bool,,}"

  local boolean_values="${__BASHKIT_CORE_LIB_BOOLEAN_TRUE}|${__BASHKIT_CORE_LIB_BOOLEAN_FALSE}"
  boolean_values+="|${__BASHKIT_CORE_LIB_BOOLEAN_ON}|${__BASHKIT_CORE_LIB_BOOLEAN_OFF}"
  boolean_values+="|${__BASHKIT_CORE_LIB_BOOLEAN_YES}|${__BASHKIT_CORE_LIB_BOOLEAN_NO}"
  readonly boolean_values

  if ! [[ "$bool" =~ ^($boolean_values)$ ]]; then
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
#   Always 0 for "save"/"restore"; exits fatally on an unknown mode.
core::with_xtrace_suppressed() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 2 "$@" || return 1
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
      log_fatal "${ERROR_OPTION_UNKNOWN}: ${mode}"
      ;;
  esac
}

# core::init_git_submodules_error(file)
#
# Checks that a required file (expected to come from a git submodule) exists,
# for use before sourcing it. Uses `echo` rather than the logging API, since
# this guards the case where the logging submodule itself hasn't been
# initialized yet.
#
# Arguments:
#   $1   Path to the file to check.
# Outputs:
#   An error to stderr naming the missing file and the fix (`git submodule
#   update --init --recursive`) if $1 is missing or does not exist.
# Returns:
#   1 if $1 is unset/empty or does not exist as a file; 0 otherwise.
# echo is intentionally used here in-case the logging submodule is unloaded
core::init_git_submodules_error() {
  f="${1:-}"
  if [[ -n "$f" ]]; then
    echo "f=\$1 positional argument must be provided."
    return 1
  fi

  if [[ ! -f "${f}" ]]; then
    # local msg="error: ${f} not found. "
    local msg="${ERROR_FILE_NOT_FOUND}: ${f} "
    msg+="Run: git submodule update --init --recursive"
    echo "${msg}" >&2
    return 1
  fi

  return 0
}

core::is_valid_var_name() {
  [[ $1 =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

if ! declare -f init_logger >/dev/null 2>&1; then
  logging_sh="${BASH_SOURCE[0]%/*}/../../../../../bash-logger/logging.sh"
  core::init_git_submodules_error "$logging_sh"
  # logging.sh should already be sourced by now.
  # This is primarily present to provide shellcheck function definitions.
  #
  # shellcheck source=../../../../../bash-logger/logging.sh
  . "$logging_sh"
  unset logging_sh

  init_logger --name "$(basename "$0")"
fi
