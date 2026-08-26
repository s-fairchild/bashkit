# shellcheck shell=bash

declare -r __vendor_bashkit_lib_virsh_domain_sourced="true"

# virsh_dom_define()
#
# Persistently defines a domain from an XML file (or "/dev/stdin" for XML piped in)
# without starting it. Mirrors `virsh define`.
#
# args:
#   * 1) xml_file - string; path to a domain XML file, or "/dev/stdin".
virsh_dom_define() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    require_operands 1 "$@" || return 1
    virsh define "$1"
}

# virsh_dom_undefine()
#
# Removes a persistent domain definition. Mirrors `virsh undefine`. Does not touch a
# running domain's live state -- destroy it first if it is active.
#
# args:
#   * 1) name - string; domain name to undefine.
virsh_dom_undefine() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    require_operands 1 "$@" || return 1
    virsh undefine "$1"
}

# virsh_dom_create()
#
# Creates and starts a transient domain directly from an XML file (or "/dev/stdin").
# The domain is never written to persistent libvirt config, and its effective XML
# (including anything merged in by the caller before this is invoked) disappears
# entirely on virsh_dom_destroy. Use this instead of virsh_dom_define + virsh_dom_start
# whenever the XML being passed in must not be persisted to disk. Mirrors `virsh create`.
#
# args:
#   * 1) xml_file - string; path to a domain XML file, or "/dev/stdin".
virsh_dom_create() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    require_operands 1 "$@" || return 1
    virsh create "$1"
}

# virsh_dom_start()
#
# Starts an already-defined (persistent) domain. Mirrors `virsh start`.
#
# args:
#   * 1) name - string; domain name to start.
virsh_dom_start() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    require_operands 1 "$@" || return 1
    virsh start "$1"
}

# virsh_dom_destroy()
#
# Forcibly stops a running domain (equivalent to pulling the power). For a transient
# domain created via virsh_dom_create, this also removes its in-memory definition
# entirely -- including any secret material that was merged into its XML at create
# time. Mirrors `virsh destroy`.
#
# args:
#   * 1) name - string; domain name to destroy.
virsh_dom_destroy() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    require_operands 1 "$@" || return 1
    virsh destroy "$1"
}

# virsh_dom_autostart()
#
# Marks a persistent domain to autostart on host boot. Mirrors `virsh autostart`.
# Not valid for transient domains -- define the domain first.
#
# args:
#   * 1) name - string; domain name to mark autostart.
virsh_dom_autostart() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    require_operands 1 "$@" || return 1
    virsh autostart "$1"
}

# virsh_dom_is_defined()
#
# Returns 0 if a domain with the given name has a persistent or live definition,
# non-zero otherwise. Thin wrapper around `virsh dominfo` for use in conditional
# expressions.
#
# args:
#   * 1) name - string; domain name to check.
virsh_dom_is_defined() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    require_operands 1 "$@" || return 1
    virsh dominfo "$1" > /dev/null 2>&1
}

# virsh_dom_is_active()
#
# Returns 0 if the domain is currently running, non-zero otherwise. Thin wrapper
# around `virsh domstate` for use in conditional expressions.
#
# args:
#   * 1) name - string; domain name to check.
virsh_dom_is_active() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    require_operands 1 "$@" || return 1
    [ "$(virsh domstate "$1" 2> /dev/null)" == "running" ]
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
    [ -f "$__vendor_bashkit_local_lib_bashkit_options_operands_utils" ] || log "$LOG_LEVEL_FATAL"
    # shellcheck source=../options-operands-utils.sh
    . "$__vendor_bashkit_local_lib_bashkit_options_operands_utils"
    unset __vendor_bashkit_local_lib_bashkit_options_operands_utils
fi
