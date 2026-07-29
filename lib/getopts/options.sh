# shellcheck shell=bash

declare -r __bashkit_lib_getopts_options_sourced="true"

is_option_duplicate() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    local -r v="${1?$(error "\$1 $ERROR_ARG_REQUIRED")}"
    local -r o="${2?$(error "\$2 $ERROR_ARG_REQUIRED")}"

    [ -z "$v" ] || fatal "-${o} ${ERROR_OPTION_DUPLICATE}"
}

declare __vendor_path="${BASH_SOURCE[0]%/*/*/*}"
if [ "${____bash_utils_base_config_logging_sourced:-}" != "true" ]; then
    declare __bash_utils_base_config_logging="${__vendor_path}/bash-utils/lib/base-config-logging.sh"
    [ -f "$__bash_utils_base_config_logging" ] || { printf '%s\n' "failed to find file: $__bash_utils_base_config_logging" >&2; exit 1; }
    # shellcheck source=../../../bash-utils/lib/base-config-logging.sh
    . "$__bash_utils_base_config_logging"
    unset __bash_utils_base_config_logging
fi
unset __vendor_path
