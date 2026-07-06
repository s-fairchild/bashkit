# shellcheck shell=bash disable=SC2034

[ "${XTRACE:-0}" -eq 1 ] && set -x

declare -r __bashkit_lib_logging_sourced="true"

# VENDOR_BASHKIT
#
# Used to set path vendored software is located.
# Useful when sourced outside of this repository (i. e. this repo is a git submodule)
#
declare -r VENDOR_BASHKIT=${VENDOR_GIT_SUBMODULES["bashkit"]:-..}

declare -F fatal > /dev/null 2>&1 || fatal() { printf '%s\n' "${1:-}" >&2; exit 1; }

if [ "${__bashkit_lib_logging_colors_sourced:=}" != "true" ]; then
    declare __lib_logging_colors="${VENDOR_BASHKIT}/lib/logging/colors.env"
    [ -f "$__lib_logging_colors" ] || fatal "file not found: $__lib_logging_colors"
    # shellcheck source=logging/colors.env
    . "$__lib_logging_colors"
    unset __lib_logging_colors
fi

if [ "${__bashkit_lib_logging_symbols_sourced:=}" != "true" ]; then
    declare __lib_logging_symbols="${VENDOR_BASHKIT}/lib/logging/symbols.env"
    [ -f "${__lib_logging_symbols}" ] || fatal "file not found: $__lib_logging_symbols"
    # shellcheck source=logging/symbols.env
    . "$__lib_logging_symbols"
    unset __lib_logging_symbols
fi

if [ "${__bashkit_lib_logging_error_messages_sourced:=}" != "true" ]; then
    declare __lib_logging_error_messages="${VENDOR_BASHKIT}/lib/logging/error-messages.env"
    [ -f "${__lib_logging_error_messages}" ] || fatal "file not found: $__lib_logging_error_messages"
    # shellcheck source=logging/error-messages.env
    . "$__lib_logging_error_messages"
    unset __lib_logging_error_messages
fi
