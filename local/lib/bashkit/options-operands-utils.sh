# shellcheck shell=bash

declare -r __vendor_bashkit_local_lib_bashkit_options_operands_utils_sourced="true"

# require_operands(<count> "$@")
#
# Validates that the caller's first <count> positional parameters are set (present, even if
# empty -- matches this repo's `${N?...}` unset-only convention, not `-z`). Logs
# "$N <ERROR_OPERAND_REQUIRED>" for the first missing one and returns 1.
#
# `return` here only unwinds require_operands itself, not its caller -- the caller must check
# the exit status and return on its own behalf:
#
#   my_fn() {
#       require_operands 3 "$@" || return 1
#       local -r a="$1" b="$2" c="$3"
#       ...
#   }
require_operands() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    local -ri count="$1"; shift
    local -i i
    for ((i = 1; i <= count; i++)); do
        if ! [ -v "$i" ]; then
            error "\$${i} ${ERROR_OPERAND_REQUIRED}"
            bashkit_print_stack_trace
            return 1
        fi
    done
}

# bashkit_print_stack_trace()
#
# Logs the current bash call stack at LOG_LEVEL_ERROR, deepest frame first (starting at this
# function's caller), so a failed contract check -- e.g. require_operands -- shows every calling
# function up to the entry-point script instead of just the one-line error. Safe to call from
# any function; each frame is logged as "at FUNCNAME (BASH_SOURCE:line)", where "line" is the
# line in that frame where it called into the next-deeper frame.
bashkit_print_stack_trace() {
    local -i i
    error "Stack trace (most recent call first):"
    for ((i = 1; i < ${#FUNCNAME[@]}; i++)); do
        error "  at ${FUNCNAME[$i]} (${BASH_SOURCE[$i]}:${BASH_LINENO[$((i - 1))]})"
    done
}


# is_option_arg_dup(<opt> <current_value>)
#
# Rejects a repeated single-value getopts flag. Call it from a `case "$opt" in ...)` arm
# *before* assigning `OPTARG`, passing the target variable's current (pre-assignment) value
# as <current_value> -- a non-empty value there means the flag was already seen once. Logs
# "-<opt> <current_value> <ERROR_OPTION_ARG_DUP>" and returns 1 if so; no-ops otherwise.
is_option_arg_dup() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    # shellcheck disable=SC2068
    require_operands 1 $@ || return 1
    local -r opt="$1"
    local -r opt_arg="$2"

    if [ -n "$opt_arg" ]; then
        error "-${opt} ${opt_arg} ${ERROR_OPTION_ARG_DUP}"
        return 1
    fi
}

# with_xtrace_suppressed(save <state_var>)
# with_xtrace_suppressed(restore <state_var>)
#
# save:    records whether xtrace (`set -x`) is currently active into
#          <state_var> (1 if active, 0 if not), then disables it. Call this
#          before running any command whose expanded arguments must not be
#          echoed -- including a command that only *tests* a value that
#          isn't known to be sensitive yet, since it's the trace line itself
#          that leaks, not the command's outcome.
# restore: re-enables xtrace if <state_var> recorded it as having been
#          active when saved. No-op otherwise. Idempotent, so it's safe to
#          call more than once against the same <state_var>.
with_xtrace_suppressed() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    
    require_operands 2 "$@" || return 1
    local -r mode="$1"
    local -n state="$2"

    case "$mode" in
        save)
            case $- in
                *x*) state=1 ;;
                *)   state=0 ;;
            esac
            set +x
            ;;
        restore)
            # if/fi (not `&&`) so this always returns 0: under this repo's
            # errexit + ERR trap, a bare `(( state )) && set -x` would abort
            # the caller whenever state is 0, since the function's own return
            # status is inherited from its last-run command.
            if (( state )); then
                set -x
            fi
            ;;
        *)
            fatal "$ERROR_OPTION_UNKNOWN: $mode"
            ;;
    esac
}

if [ "${__bash_logger_adapter_sourced:-}" != "true" ]; then
    declare __bash_logger_adapter_path="${BASH_SOURCE[0]%/*}/../../../../bash-logger-adapter/adapter.sh"
    [ -f "$__bash_logger_adapter_path" ] || { printf '%s\n' "failed to find file: $__bash_logger_adapter_sourced" >&2; exit 1; }
    # shellcheck source=../../../../bash-logger-adapter/adapter.sh
    . "$__bash_logger_adapter_path"
    unset __bash_logger_adapter_path
fi
