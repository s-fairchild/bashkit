# shellcheck shell=bash

declare -r __vendor_bashkit_lib_network_validate_sourced="true"

# validate_url()
# Returns 1 if the URL provided is invalid
#
# args:
# 1) url - string; url string to be validated
validate_url() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    
    require_operands 1 "$@" || return 1
    local -r url="$1"

    if [ -z "$url" ]; then
        log_error "\$1 ${ERROR_STRING_EMPTY}"
        return 1
    fi

    local -r regex='^(https?|ftp|file)://[-[:alnum:]\+&@#/%?=~_|!:,.;]*[-[:alnum:]\+&@#/%=~_|\.]*$'

    if [[ ! "$url" =~ $regex ]]; then
        log_error "\$1 ${ERROR_REGEX_FAIL}: ${regex}"
        return 1
    fi
}

if [ "${__vendor_bash_logger_adapter_sourced:-}" != "true" ]; then
    declare __vendor_bash_logger_adapter="${BASH_SOURCE[0]%/*}/../../../../../bash-logger-adapter.sh"
    [ -f "$__vendor_bash_logger_adapter" ] || { printf '%s\n' "failed to find file: $__vendor_bash_logger_adapter" >&2; exit 1; }
    # shellcheck source=../../../../../bash-logger-adapter.sh
    . "$__vendor_bash_logger_adapter"
    unset __vendor_bash_logger_adapter
fi

if [ "${__vendor_bashkit_utils_options_sourced:-}" != "true" ]; then
    declare __vendor_bashkit_utils_options="${BASH_SOURCE[0]%/*}/../options.sh"
    [ -f "$__vendor_bashkit_utils_options" ] || { printf '%s\n' "failed to find file: $__vendor_bashkit_utils_options" >&2; exit 1; }
    # shellcheck source=../options.sh
    . "$__vendor_bashkit_utils_options"
    unset __vendor_bashkit_utils_options
fi

