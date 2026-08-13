# shellcheck shell=bash

declare -r __vendor_bashkit_lib_virsh_network_sourced="true"

virsh_net_define() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    require_operands 1 "$@" || return 1
    local -r network_name="$1"
    local -r network_desc="${2:-}"

    local -a network_xml=(
        "<network>"
        "<name>${network_name}</name>"
    )

    [ -n "$network_desc" ] && network_xml+=("<description>${network_desc}</description>")

    local network_xml_file
    network_xml_file="$(mktemp --suffix="${FUNCNAME[0]}.xml")"
    trap 'rm -f "$network_xml_file"' RETURN
    printf '%s' "${network_xml[@]}" > "$network_xml_file"
    virsh net-define "$network_xml_file"
}

virsh_net_activate() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    require_operands 1 "$@" || return 1
    virsh net-start "$1"
}

virsh_net_destroy() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    require_operands 1 "$@" || return 1
    virsh net-destroy "$1"
}

declare -r __NETWORK_KEY_ACTIVE="Active"
declare -r __NETWORK_KEY_PERSISTENT="Persistent"
declare -r __NETWORK_KEY_AUTOSTART="Autostart"

virsh_net_is_defined() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    require_operands 1 "$@" || return 1
    virsh net-uuid "$1" > /dev/null 2>&1
}

virsh_net_is_active() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    require_operands 1 "$@" || return 1
    virsh_net_parse_info "$1" "$__NETWORK_KEY_ACTIVE"
}

virsh_net_is_persistent() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    require_operands 1 "$@" || return 1
    virsh_net_parse_info "$1" "$__NETWORK_KEY_PERSISTENT"
}

virsh_net_is_autostart() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    require_operands 1 "$@" || return 1
    virsh_net_parse_info "$1" "$__NETWORK_KEY_AUTOSTART"
}

virsh_net_autostart() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    require_operands 1 "$@" || return 1
    virsh net-autostart "$1"
}

virsh_net_parse_info() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    require_operands 2 "$@" || return 1
    local -r network="$1"
    local -r search="$2"

    local -r regex_test="(${__NETWORK_KEY_ACTIVE}|${__NETWORK_KEY_PERSISTENT}|${__NETWORK_KEY_AUTOSTART})"
    if ! [[ $search =~ $regex_test ]]; then
        log_error "\$1 ${ERROR_REGEX_FAIL}: ${regex_test}"
        return 1
    fi

    virsh net-info "$network" \
        | grep "$search" \
        | tr -d ' ' \
        | cut -d : -f 2 \
        | grep -q "yes"
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
