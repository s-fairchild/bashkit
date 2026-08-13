# shellcheck shell=bash

declare -r __vendor_bashkit_utils_options_sourced="true"

is_option_arg_dup() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    require_operands 2 "$@" || return 1
    local -r opt="$1"
    local -r opt_arg="$2"

    if [ -n "$opt_arg" ]; then
        log_error "-${opt} ${opt_arg} ${ERROR_OPTION_ARG_DUP}"
        return 1
    fi
}

# with_xtrace_suppressed save <state_var>
# with_xtrace_suppressed restore <state_var>
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
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    
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
            log_fatal "$ERROR_OPTION_UNKNOWN: $mode"
            ;;
    esac
}

if [ "${__vendor_bash_logger_adapter_sourced:-}" != "true" ]; then
    declare __vendor_bash_logger_adapter="${BASH_SOURCE[0]%/*}/../../../../bash-logger-adapter.sh"
    [ -f "$__vendor_bash_logger_adapter" ] || { printf '%s\n' "failed to find file: $__vendor_bash_logger_adapter" >&2; exit 1; }
    # shellcheck source=../../../../bash-logger-adapter.sh
    . "$__vendor_bash_logger_adapter"
    unset __vendor_bash_logger_adapter
fi
