# shellcheck shell=bash

declare -r __vendor_bashkit_utils_suppressed_sourced="true"

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
    local -r mode="${1?$(error "\$1 $ERROR_ARG_REQUIRED")}"
    local -n state="${2?$(error "\$2 $ERROR_ARG_REQUIRED")}"

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

if [ "${__vendor_bash_logger_compat_sourced:-}" != "true" ]; then
    declare __vendor_bash_logger_compat="hack/vendor/bash-logger-compat.sh"
    [ -f "$__vendor_bash_logger_compat" ] || { printf '%s\n' "failed to find file: $__vendor_bash_logger_compat" >&2; exit 1; }
    # shellcheck source=../../bash-logger-compat.sh
    . "$__vendor_bash_logger_compat"
    unset __vendor_bash_logger_compat
fi
