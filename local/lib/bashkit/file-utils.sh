# shellcheck shell=bash

declare -r __vendor_bashkit_lib_file_utils_sourced="true"
declare -r __error_no_file="a file must be provided to read into memory."

read_file_builtin() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    if [ -t 0 ]; then
        local -r input="$(cat)"
    elif (( $# )); then
        local -r input="$*"
    else
        log_error "$ERROR_ARG_REQUIRED: $__error_no_file"
    fi
    log_sensitive "$(declare -p input)"

    local -r output="$(<"$input")"
    log_sensitive "$(declare -p output)"

    if [ -z "$output" ]; then
        log_error "failed to read file $1 into memory."
        return 1
    fi

    printf "%s" "$output"
}

read_file_preserve_newlines() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    if [ -t 0 ]; then
        local -r input="$(cat)"
    elif (( $# )); then
        local -r input="$*"
    else
        log_error "$ERROR_ARG_REQUIRED: $__error_no_file"
    fi
    log_sensitive "$(declare -p input)"

    local output
    IFS= read -r -d '' output < "$input" || true
    log_sensitive "$(declare -p output)"

    if [ -z "$output" ]; then
        log_error "failed to read file $1 into memory."
        return 1
    fi

    printf "%s" "$output"
}

parse_file_extension() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    if [ -t 0 ]; then
        local -r input="$(cat)"
    elif (( $# )); then
        local -r input="$*"
    else
        log_error "$ERROR_ARG_REQUIRED: $__error_no_file"
    fi
    # log_debug should be fine as this *should* only be a file extension.
    # but just to be on the safe side log_sensitive is used here, in the event sensitive data is accidentally here.
    log_sensitive "$(declare -p input)"

    local output
    output="$(basename "$input")"
    log_sensitive "$(declare -p output)"
    output="${output##*.}"
    log_sensitive "$(declare -p output)"

    if [ -z "$output" ]; then
        # log_error "failed to parse checksum value."
        echo "failed to parse checksum value."
        return 1
    fi

    printf "%s" "$output"
}

if [ "${__bash_logger_adapter_sourced:-}" != "true" ]; then
    declare __bash_logger_adapter_path="${BASH_SOURCE[0]%/*}/../../../../bash-logger-adapter/adapter.sh"
    [ -f "$__bash_logger_adapter_path" ] || { printf '%s\n' "failed to find file: $__bash_logger_adapter_sourced" >&2; exit 1; }
    # shellcheck source=../../../../bash-logger-adapter/adapter.sh
    . "$__bash_logger_adapter_path"
    unset __bash_logger_adapter_path
fi
