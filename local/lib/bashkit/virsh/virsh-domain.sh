# shellcheck shell=bash
#
# Thin, operand-validated wrappers around `virsh` domain (VM) subcommands.

declare -r __vendor_bashkit_lib_virsh_domain_sourced="true"

# virsh_dom_define(xml_file)
#
# Persistently defines a domain from an XML file (or "/dev/stdin" for XML
# piped in) without starting it. Mirrors `virsh define`.
#
# Globals:
#   None.
# Arguments:
#   $1   Path to a domain XML file, or "/dev/stdin".
# Outputs:
#   Whatever `virsh define` writes.
# Returns:
#   The exit status of `virsh define`.
virsh_dom_define() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return 1
  virsh define "$1"
}

# virsh_dom_undefine(name)
#
# Removes a persistent domain definition. Mirrors `virsh undefine`. Does
# not touch a running domain's live state -- destroy it first if it is
# active.
#
# Globals:
#   None.
# Arguments:
#   $1   Domain name to undefine.
# Outputs:
#   Whatever `virsh undefine` writes.
# Returns:
#   The exit status of `virsh undefine`.
virsh_dom_undefine() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return 1
  virsh undefine "$1"
}

# virsh_dom_create(xml_file)
#
# Creates and starts a transient domain directly from an XML file (or
# "/dev/stdin"). The domain is never written to persistent libvirt config,
# and its effective XML (including anything merged in by the caller before
# this is invoked) disappears entirely on virsh_dom_destroy. Use this
# instead of virsh_dom_define + virsh_dom_start whenever the XML being
# passed in must not be persisted to disk. Mirrors `virsh create`.
#
# Globals:
#   None.
# Arguments:
#   $1   Path to a domain XML file, or "/dev/stdin".
# Outputs:
#   Whatever `virsh create` writes.
# Returns:
#   The exit status of `virsh create`.
virsh_dom_create() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return 1
  virsh create "$1"
}

# virsh_dom_start(name)
#
# Starts an already-defined (persistent) domain. Mirrors `virsh start`.
#
# Globals:
#   None.
# Arguments:
#   $1   Domain name to start.
# Outputs:
#   Whatever `virsh start` writes.
# Returns:
#   The exit status of `virsh start`.
virsh_dom_start() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return 1
  virsh start "$1"
}

# virsh_dom_destroy(name)
#
# Forcibly stops a running domain (equivalent to pulling the power). For a
# transient domain created via virsh_dom_create, this also removes its
# in-memory definition entirely -- including any secret material that was
# merged into its XML at create time. Mirrors `virsh destroy`.
#
# Globals:
#   None.
# Arguments:
#   $1   Domain name to destroy.
# Outputs:
#   Whatever `virsh destroy` writes.
# Returns:
#   The exit status of `virsh destroy`.
virsh_dom_destroy() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return 1
  virsh destroy "$1"
}

# virsh_dom_autostart(name)
#
# Marks a persistent domain to autostart on host boot. Mirrors
# `virsh autostart`. Not valid for transient domains -- define the domain
# first.
#
# Globals:
#   None.
# Arguments:
#   $1   Domain name to mark autostart.
# Outputs:
#   Whatever `virsh autostart` writes.
# Returns:
#   The exit status of `virsh autostart`.
virsh_dom_autostart() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return 1
  virsh autostart "$1"
}

# virsh_dom_is_defined(name)
#
# Returns 0 if a domain with the given name has a persistent or live
# definition, non-zero otherwise. Thin wrapper around `virsh dominfo` for
# use in conditional expressions.
#
# Globals:
#   None.
# Arguments:
#   $1   Domain name to check.
# Outputs:
#   None (virsh's own output is discarded).
# Returns:
#   0 if the domain is defined; non-zero otherwise.
virsh_dom_is_defined() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return 1
  virsh dominfo "$1" > /dev/null 2>&1
}

# virsh_dom_is_active(name)
#
# Returns 0 if the domain is currently running, non-zero otherwise. Thin
# wrapper around `virsh domstate` for use in conditional expressions.
#
# Globals:
#   None.
# Arguments:
#   $1   Domain name to check.
# Outputs:
#   None.
# Returns:
#   0 if the domain's state is "running"; non-zero otherwise.
virsh_dom_is_active() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return 1
  [[ "$(virsh domstate "$1" 2> /dev/null)" == "running" ]]
}

if [[ "${__bash_logger_adapter_sourced:-}" != "true" ]]; then
  declare __bash_logger_adapter_path="${BASH_SOURCE[0]%/*}/../../../../../bash-logger-adapter/adapter.sh"
  [[ -f "${__bash_logger_adapter_path}" ]] || { printf '%s\n' "failed to find file: ${__bash_logger_adapter_path}" >&2; exit 1; }
  # shellcheck source=../../../../../bash-logger-adapter/adapter.sh
  . "${__bash_logger_adapter_path}"
  unset __bash_logger_adapter_path
fi

if [[ "${__bashkit_core_sourced:-}" != "true" ]]; then
  declare __bashkit_core="${BASH_SOURCE[0]%/*}/../core/contract-utils.sh"
  [[ -f "${__bashkit_core}" ]] || fatal "${ERROR_FILE_NOT_FOUND}: ${__bashkit_core}"
  # shellcheck source=../core/contract-utils.sh
  . "${__bashkit_core}"
  unset __bashkit_core
fi
