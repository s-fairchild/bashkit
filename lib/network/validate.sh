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

