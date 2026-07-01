# shellcheck shell=bash

declare -r __hack_lib_file_utils_sourced="true"
declare -r __error_no_file="a file must be provided to read into memory."

read_file_builtin() {
    if [ -t 0 ]; then
        local -r input="$(cat)"
    elif (( $# )); then
        local -r input="$*"
    else
        error "$ERROR_ARG_REQUIRED: $__error_no_file"
    fi
    debug "$(declare -p input)"

    local -r output="$(<"$input")"
    debug "$(declare -p output)"

    if [ -z "$output" ]; then
        error "failed to read file $1 into memory."
        return 1
    fi

    printf "%s" "$output"
}

read_file_preserve_newlines() {
    if [ -t 0 ]; then
        local -r input="$(cat)"
    elif (( $# )); then
        local -r input="$*"
    else
        error "$ERROR_ARG_REQUIRED: $__error_no_file"
    fi
    debug "$(declare -p input)"

    local output
    IFS= read -r -d '' output < "$input" || true
    debug "$(declare -p output)"

    if [ -z "$output" ]; then
        error "failed to read file $1 into memory."
        return 1
    fi

    printf "%s" "$output"
}

parse_file_extension() {
    if [ -t 0 ]; then
        local -r input="$(cat)"
    elif (( $# )); then
        local -r input="$*"
    else
        error "$ERROR_ARG_REQUIRED: $__error_no_file"
    fi
    debug "$(declare -p input)"

    local output
    output="$(basename "$input")"
    debug "$(declare -p output)"
    output="${output##*.}"
    debug "$(declare -p output)"

    if [ -z "$output" ]; then
        # error "failed to parse checksum value."
        echo "failed to parse checksum value."
        return 1
    fi

    printf "%s" "$output"
}

if [ "${__lib_vendor_bash_utils_logging_sourced:-}" != "true" ]; then
    declare -r lib_vendor_bash_utils_logging="hack/lib/vendor-bash-utils-logging.sh"
    [ -f "$lib_vendor_bash_utils_logging" ] || { printf '%s\n' "failed to find file: $lib_opt_bash_utils_logging" >&2; exit 1; }
    # shellcheck source=../../../lib/vendor-bash-utils-logging.sh
    . "$lib_vendor_bash_utils_logging"
fi
