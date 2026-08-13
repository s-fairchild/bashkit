# shellcheck shell=bash

declare -r __vendor_bashkit_lib_virsh_pool_sourced="true"

# virsh_pool_define()
#
# Persistently defines a storage pool from an XML file (or "/dev/stdin"). Mirrors
# `virsh pool-define`. The pool's target directory is not created by this call --
# see virsh_pool_build().
#
# args:
#   * 1) xml_file - string; path to a storage pool XML file, or "/dev/stdin".
virsh_pool_define() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    local -r xml_file="${1?$(fatal "\$1 ${ERROR_OPERAND_REQUIRED}")}"

    virsh pool-define "$xml_file"
}

# virsh_pool_build()
#
# Creates the on-disk target directory for a defined pool. Mirrors `virsh pool-build`.
# Safe to call on a pool whose target already exists -- passes --no-overwrite so an
# already-built pool is left untouched instead of erroring.
#
# args:
#   * 1) name - string; pool name to build.
virsh_pool_build() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    local -r name="${1?$(fatal "\$1 ${ERROR_OPERAND_REQUIRED}")}"

    virsh pool-build "$name" --no-overwrite
}

# virsh_pool_start()
#
# Starts (activates) a defined storage pool. Mirrors `virsh pool-start`.
#
# args:
#   * 1) name - string; pool name to start.
virsh_pool_start() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    local -r name="${1?$(fatal "\$1 ${ERROR_OPERAND_REQUIRED}")}"

    virsh pool-start "$name"
}

# virsh_pool_autostart()
#
# Marks a defined storage pool to autostart on host boot. Mirrors `virsh pool-autostart`.
#
# args:
#   * 1) name - string; pool name to mark autostart.
virsh_pool_autostart() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    local -r name="${1?$(fatal "\$1 ${ERROR_OPERAND_REQUIRED}")}"

    virsh pool-autostart "$name"
}

# virsh_pool_is_defined()
#
# Returns 0 if a storage pool with the given name has a persistent definition,
# non-zero otherwise. Thin wrapper around `virsh pool-uuid` for use in conditional
# expressions.
#
# args:
#   * 1) name - string; pool name to check.
virsh_pool_is_defined() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    local -r name="${1?$(fatal "\$1 ${ERROR_OPERAND_REQUIRED}")}"

    virsh pool-uuid "$name" > /dev/null 2>&1
}

# virsh_pool_is_active()
#
# Returns 0 if the storage pool is currently running, non-zero otherwise. Thin wrapper
# around `virsh pool-info` for use in conditional expressions.
#
# args:
#   * 1) name - string; pool name to check.
virsh_pool_is_active() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    local -r name="${1?$(fatal "\$1 ${ERROR_OPERAND_REQUIRED}")}"

    virsh pool-info "$name" 2> /dev/null | grep -q '^State: *running'
}

# virsh_vol_create()
#
# Creates a storage volume within a pool from an XML file (or "/dev/stdin"). Mirrors
# `virsh vol-create`. The pool must already be defined and active.
#
# args:
#   * 1) pool - string; name of the pool to create the volume in.
#   * 2) xml_file - string; path to a storage volume XML file, or "/dev/stdin".
virsh_vol_create() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    local -r pool="${1?$(fatal "\$1 ${ERROR_OPERAND_REQUIRED}")}"
    local -r xml_file="${2?$(fatal "\$2 ${ERROR_OPERAND_REQUIRED}")}"

    virsh vol-create "$pool" "$xml_file"
}

# virsh_vol_is_present()
#
# Returns 0 if a volume with the given name exists within the given pool, non-zero
# otherwise. Thin wrapper around `virsh vol-info` for use in conditional expressions.
#
# args:
#   * 1) pool - string; name of the pool to check.
#   * 2) vol - string; volume name to check for.
virsh_vol_is_present() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    local -r pool="${1?$(fatal "\$1 ${ERROR_OPERAND_REQUIRED}")}"
    local -r vol="${2?$(fatal "\$2 ${ERROR_OPERAND_REQUIRED}")}"

    virsh vol-info --pool "$pool" "$vol" > /dev/null 2>&1
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
