# shellcheck shell=bash

declare -r __vendor_bashkit_lib_virsh_sourced="true"

virsh() {
    sudo bash -c 'command virsh "$@"' bash "$@"
}
export -f virsh

virt-install() {
    command virt-install "$@"
}
export -f virt-install
