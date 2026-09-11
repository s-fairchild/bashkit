# shellcheck shell=bash
#
# Thin, operand-validated wrappers around `virsh` domain (VM) subcommands.

[[ "${XTRACE:-0}" -eq 1 ]] && set -x

readonly __BASHKIT_LIB_VIRSH_DOMAIN_SOURCED="true"

# virsh::domain_define(xml_file)
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
virsh::domain_define() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return 1
  virsh define "$1"
}

# virsh::domain_undefine(name)
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
virsh::domain_undefine() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return 1
  virsh undefine "$1"
}

# virsh::domain_create(xml_file)
#
# Creates and starts a transient domain directly from an XML file (or
# "/dev/stdin"). The domain is never written to persistent libvirt config,
# and its effective XML (including anything merged in by the caller before
# this is invoked) disappears entirely on virsh::domain_destroy. Use this
# instead of virsh::domain_define + virsh::domain_start whenever the XML
# being passed in must not be persisted to disk. Mirrors `virsh create`.
#
# Globals:
#   None.
# Arguments:
#   $1   Path to a domain XML file, or "/dev/stdin".
# Outputs:
#   Whatever `virsh create` writes.
# Returns:
#   The exit status of `virsh create`.
virsh::domain_create() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return 1
  virsh create "$1"
}

# virsh::domain_start(name)
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
virsh::domain_start() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return 1
  virsh start "$1"
}

# virsh::domain_destroy(name)
#
# Forcibly stops a running domain (equivalent to pulling the power). For a
# transient domain created via virsh::domain_create, this also removes its
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
virsh::domain_destroy() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return 1
  virsh destroy "$1"
}

# virsh::domain_autostart(name)
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
virsh::domain_autostart() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return 1
  virsh autostart "$1"
}

# virsh::domain_is_defined(name)
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
virsh::domain_is_defined() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return 1
  virsh dominfo "$1" > /dev/null 2>&1
}

# virsh::domain_is_active(name)
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
virsh::domain_is_active() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return 1
  [[ "$(virsh domstate "$1" 2> /dev/null)" == "running" ]]
}

if [[ "${__BASHKIT_LIB_CORE_CONTRACT_UTILS_SOURCED:-}" != "true" ]]; then
  # shellcheck source=../core/contract-utils.sh
  . "${BASH_SOURCE[0]%/*}/../core/contract-utils.sh"
fi
