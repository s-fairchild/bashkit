# shellcheck shell=bash

# validate_url()
# Returns 1 if the URL provided is invalid
#
# args:
# 1) url - string; url string to be validated
validate_url() {
    local -r url="${1}"
    log "starting"

    if [ -z "$url" ]; then
        abort "url is empty."
    fi

    local -r regex='^(https?|ftp|file)://[-[:alnum:]\+&@#/%?=~_|!:,.;]*[-[:alnum:]\+&@#/%=~_|\.]*$'

    if [[ ! "$url" =~ $regex ]]; then
        log "The string \"$url\" is NOT a valid URL."
        return 1
    fi
}

declare __bashkit_path="${BASH_SOURCE[0]%/*/*}"
if [ "${__bash_utils_base_config_logging_sourced:-}" != "true" ]; then
    declare __bash_utils_base_config_logging="${__bashkit_path}/../bash-logger-compat.sh"
    [ -f "$__bash_utils_base_config_logging" ] || { printf '%s\n' "failed to find file: $__bash_utils_base_config_logging" >&2; exit 1; }
    # shellcheck source=../../../bash-logger-compat.sh
    . "$__bash_utils_base_config_logging"
    unset __bash_utils_base_config_logging
fi
unset __bashkit_path

