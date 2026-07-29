# shellcheck shell=bash

declare -r __vendor_bashkit_utils_options_sourced="true"

is_option_duplicate() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    local -r v="${1?$(error "\$1 $ERROR_ARG_REQUIRED")}"
    local -r o="${2?$(error "\$2 $ERROR_ARG_REQUIRED")}"

    [ -z "$v" ] || log_fatal "-${o} ${ERROR_OPTION_DUPLICATE}"
}

if [ "${__vendor_bash_logger_compat_sourced:-}" != "true" ]; then
    declare __vendor_bash_logger_compat="hack/vendor/bash-logger-compat.sh"
    [ -f "$__vendor_bash_logger_compat" ] || { printf '%s\n' "failed to find file: $__vendor_bash_logger_compat" >&2; exit 1; }
    # shellcheck source=../../bash-logger-compat.sh
    . "$__vendor_bash_logger_compat"
    unset __vendor_bash_logger_compat
fi
