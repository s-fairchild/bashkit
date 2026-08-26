# shellcheck shell=bash

declare -r __vendor_bashkit_lib_virsh_network_sourced="true"

virsh_net_define() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

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
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    require_operands 1 "$@" || return 1
    virsh net-start "$1"
}

virsh_net_destroy() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    require_operands 1 "$@" || return 1
    virsh net-destroy "$1"
}

declare -r __NETWORK_KEY_ACTIVE="Active"
declare -r __NETWORK_KEY_PERSISTENT="Persistent"
declare -r __NETWORK_KEY_AUTOSTART="Autostart"

virsh_net_is_defined() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    require_operands 1 "$@" || return 1
    virsh net-uuid "$1" > /dev/null 2>&1
}

virsh_net_is_active() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    require_operands 1 "$@" || return 1
    virsh_net_parse_info "$1" "$__NETWORK_KEY_ACTIVE"
}

virsh_net_is_persistent() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    require_operands 1 "$@" || return 1
    virsh_net_parse_info "$1" "$__NETWORK_KEY_PERSISTENT"
}

virsh_net_is_autostart() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    require_operands 1 "$@" || return 1
    virsh_net_parse_info "$1" "$__NETWORK_KEY_AUTOSTART"
}

virsh_net_autostart() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    require_operands 1 "$@" || return 1
    virsh net-autostart "$1"
}

virsh_net_parse_info() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    require_operands 2 "$@" || return 1
    local -r network="$1"
    local -r search="$2"

    local -r regex_test="(${__NETWORK_KEY_ACTIVE}|${__NETWORK_KEY_PERSISTENT}|${__NETWORK_KEY_AUTOSTART})"
    if ! [[ $search =~ $regex_test ]]; then
        error "\$1 ${ERROR_REGEX_FAIL}: ${regex_test}"
        return 1
    fi

    virsh net-info "$network" \
        | grep "$search" \
        | tr -d ' ' \
        | cut -d : -f 2 \
        | grep -q "yes"
}

if [ "${__bash_logger_adapter_sourced:-}" != "true" ]; then
    declare __bash_logger_adapter_path="${BASH_SOURCE[0]%/*}/../../../../../bash-logger-adapter/adapter.sh"
    [ -f "$__bash_logger_adapter_path" ] || { printf '%s\n' "failed to find file: $__bash_logger_adapter_sourced" >&2; exit 1; }
    # shellcheck source=../../../../../bash-logger-adapter/adapter.sh
    . "$__bash_logger_adapter_path"
    unset __bash_logger_adapter_path
fi

if [ "${__vendor_bashkit_local_lib_bashkit_options_operands_utils_sourced:-}" != "true" ]; then
    declare __vendor_bashkit_local_lib_bashkit_options_operands_utils="${BASH_SOURCE[0]%/*}/../options-operands-utils.sh"
    [ -f "$__vendor_bashkit_local_lib_bashkit_options_operands_utils" ] || fatal "${ERROR_FILE_NOT_FOUND}: ${__vendor_bashkit_local_lib_bashkit_options_operands_utils}"
    # shellcheck source=../options-operands-utils.sh
    . "$__vendor_bashkit_local_lib_bashkit_options_operands_utils"
    unset __vendor_bashkit_local_lib_bashkit_options_operands_utils
fi
