# shellcheck shell=bash

declare -r __vendor_bashkit_lib_virsh_network_sourced="true"

virsh_net_define() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    local -r network_name="${1?$(fatal "\$1 ${ERROR_ARG_REQUIRED}")}"
    local -r network_desc="${2:-}"

    local -a network_xml=(
        "<network>"
        "<name>${network_name}</name>"
    )

    [ -n "$network_desc" ] && network_xml+=("<description>${network_desc}</description>")

    network_xml+=(
    "<bridge name=\"virbr1\" stp=\"on\" delay=\"0\"/>"
    "<forward mode=\"nat\"/>"
    "<ip address=\"192.168.150.1\" netmask=\"255.255.255.0\">"
    "<dhcp>"
    "<range start=\"192.168.150.2\" end=\"192.168.150.254\"/>"
    "</dhcp>"
    "</ip>"
    "</network>"
    )

    local network_xml_file
    network_xml_file="$(mktemp --suffix="${FUNCNAME[0]}.xml")"
    trap 'rm -f "$network_xml_file"' RETURN
    printf '%s' "${network_xml[@]}" > "$network_xml_file"
    virsh net-define "$network_xml_file"
}

virsh_net_activate() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    local -r network="${1?$(fatal "\$1 ${ERROR_ARG_REQUIRED}")}"

    virsh net-start "$network"
}

virsh_net_destroy() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    local -r network="${1?$(fatal "\$1 ${ERROR_ARG_REQUIRED}")}"

    virsh net-destroy "$network"
}

declare -r __NETWORK_KEY_ACTIVE="Active"
declare -r __NETWORK_KEY_PERSISTENT="Persistent"
declare -r __NETWORK_KEY_AUTOSTART="Autostart"

virsh_net_is_defined() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    local -r network="${1?$(fatal "\$1 ${ERROR_ARG_REQUIRED}")}"

    virsh net-uuid "$network" > /dev/null 2>&1
}

virsh_net_is_active() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    local -r network="${1?$(fatal "\$1 ${ERROR_ARG_REQUIRED}")}"

    virsh_net_parse_info "$network" "$__NETWORK_KEY_ACTIVE"
}

virsh_net_is_persistent() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    local -r network="${1?$(fatal "\$1 ${ERROR_ARG_REQUIRED}")}"

    virsh_net_parse_info "$network" "$__NETWORK_KEY_PERSISTENT"
}

virsh_net_is_autostart() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    local -r network="${1?$(fatal "\$1 ${ERROR_ARG_REQUIRED}")}"

    virsh_net_parse_info "$network" "$__NETWORK_KEY_AUTOSTART"
}

virsh_net_autostart() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    local -r network="${1?$(fatal "\$1 ${ERROR_ARG_REQUIRED}")}"

    virsh net-autostart "$network"
}

virsh_net_parse_info() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    local -r network="${1?$(fatal "\$1 ${ERROR_ARG_REQUIRED}")}"
    local -r search="${2?$(fatal "\$2 ${ERROR_ARG_REQUIRED}")}"

    local -r regex_test="(${__NETWORK_KEY_ACTIVE}|${__NETWORK_KEY_PERSISTENT}|${__NETWORK_KEY_AUTOSTART})"
    [[ $search =~ $regex_test ]] || log_fatal "\$1 must match regex: ${regex_test}"

    virsh net-info "$network" \
        | grep "$search" \
        | tr -d ' ' \
        | cut -d : -f 2 \
        | grep -q "yes"
}

if [ "${__vendor_bash_logger_compat_sourced:-}" != "true" ]; then
    declare __vendor_bash_logger_compat="hack/vendor/bash-logger-compat.sh"
    [ -f "$__vendor_bash_logger_compat" ] || { printf '%s\n' "failed to find file: $__vendor_bash_logger_compat" >&2; exit 1; }
    # shellcheck source=../../../bash-logger-compat.sh
    . "$__vendor_bash_logger_compat"
    unset __vendor_bash_logger_compat
fi
if [ "${__vendor_bashkit_lib_virsh_sourced:-}" != "true" ]; then
    declare __vendor_bashkit_lib_virsh="hack/vendor/bashkit/lib/virsh/virsh.sh"
    [ -f "$__vendor_bashkit_lib_virsh" ] || log_fatal "${ERROR_FILE_NOT_FOUND}: ${__vendor_bashkit_lib_virsh}"
    # shellcheck source=virsh.sh
    . "$__vendor_bashkit_lib_virsh"
    unset __vendor_bashkit_lib_virsh
fi
