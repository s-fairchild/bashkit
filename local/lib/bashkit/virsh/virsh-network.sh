# shellcheck shell=bash
#
# Thin, operand-validated wrappers around `virsh` network subcommands.

[[ "${XTRACE:-0}" -eq 1 ]] && set -x

readonly __BASHKIT_LIB_VIRSH_NETWORK_SOURCED="true"
if [[ "${__BASHKIT_LIB_CORE_CONTRACT_UTILS_SOURCED:-}" != "true" ]]; then
  # shellcheck source=../core/contract-utils.sh
  . "${BASH_SOURCE[0]%/*}/../core/contract-utils.sh"
fi

#####################
### Globals Start ###
#####################

readonly __BASHKIT_VIRSH_NETWORK_KEY_ACTIVE="Active"
readonly __BASHKIT_VIRSH_NETWORK_KEY_PERSISTENT="Persistent"
readonly __BASHKIT_VIRSH_NETWORK_KEY_AUTOSTART="Autostart"

###################
### Globals End ###
###################

# virsh::net_define(name [description])
#
# Persistently defines a libvirt network from a minimal generated XML
# document (name + optional description). Mirrors `virsh net-define`.
#
# Globals:
#   None.
# Arguments:
#   $1   Network name.
#   $2   Optional network description.
# Outputs:
#   Whatever `virsh net-define` writes.
# Returns:
#   The exit status of `virsh net-define`.
virsh::net_define() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return 1
  local -r network_name="$1"
  local -r network_desc="${2:-}"

  local -a network_xml=(
    "<network>"
    "<name>${network_name}</name>"
  )

  [[ -n "${network_desc}" ]] && network_xml+=("<description>${network_desc}</description>")

  local network_xml_file
  network_xml_file="$(mktemp --suffix="${FUNCNAME[0]}.xml")"
  trap 'rm -f "${network_xml_file}"' RETURN
  printf '%s' "${network_xml[@]}" > "${network_xml_file}"
  virsh net-define "${network_xml_file}"
}

# virsh::net_activate(name)
#
# Starts (activates) a defined network. Mirrors `virsh net-start`.
#
# Globals:
#   None.
# Arguments:
#   $1   Network name to activate.
# Outputs:
#   Whatever `virsh net-start` writes.
# Returns:
#   The exit status of `virsh net-start`.
virsh::net_activate() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return 1
  virsh net-start "$1"
}

# virsh::net_destroy(name)
#
# Stops (deactivates) a running network. Mirrors `virsh net-destroy`.
#
# Globals:
#   None.
# Arguments:
#   $1   Network name to destroy.
# Outputs:
#   Whatever `virsh net-destroy` writes.
# Returns:
#   The exit status of `virsh net-destroy`.
virsh::net_destroy() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return 1
  virsh net-destroy "$1"
}

# virsh::net_is_defined(name)
#
# Returns 0 if a network with the given name has a persistent definition,
# non-zero otherwise. Thin wrapper around `virsh net-uuid` for use in
# conditional expressions.
#
# Globals:
#   None.
# Arguments:
#   $1   Network name to check.
# Outputs:
#   None.
# Returns:
#   0 if the network is defined; non-zero otherwise.
virsh::net_is_defined() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return 1
  virsh net-uuid "$1" > /dev/null 2>&1
}

# virsh::net_is_active(name)
#
# Returns 0 if the network is currently active, non-zero otherwise. Thin
# wrapper around `virsh net-info` for use in conditional expressions.
#
# Globals:
#   __BASHKIT_VIRSH_NETWORK_KEY_ACTIVE
# Arguments:
#   $1   Network name to check.
# Outputs:
#   None.
# Returns:
#   0 if the network's "Active" field is "yes"; non-zero otherwise.
virsh::net_is_active() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return 1
  virsh::net_parse_info "$1" "${__BASHKIT_VIRSH_NETWORK_KEY_ACTIVE}"
}

# virsh::net_is_persistent(name)
#
# Returns 0 if the network has a persistent definition, non-zero
# otherwise. Thin wrapper around `virsh net-info` for use in conditional
# expressions.
#
# Globals:
#   __BASHKIT_VIRSH_NETWORK_KEY_PERSISTENT
# Arguments:
#   $1   Network name to check.
# Outputs:
#   None.
# Returns:
#   0 if the network's "Persistent" field is "yes"; non-zero otherwise.
virsh::net_is_persistent() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return 1
  virsh::net_parse_info "$1" "${__BASHKIT_VIRSH_NETWORK_KEY_PERSISTENT}"
}

# virsh::net_is_autostart(name)
#
# Returns 0 if the network is marked to autostart, non-zero otherwise.
# Thin wrapper around `virsh net-info` for use in conditional expressions.
#
# Globals:
#   __BASHKIT_VIRSH_NETWORK_KEY_AUTOSTART
# Arguments:
#   $1   Network name to check.
# Outputs:
#   None.
# Returns:
#   0 if the network's "Autostart" field is "yes"; non-zero otherwise.
virsh::net_is_autostart() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return 1
  virsh::net_parse_info "$1" "${__BASHKIT_VIRSH_NETWORK_KEY_AUTOSTART}"
}

# virsh::net_autostart(name)
#
# Marks a defined network to autostart on host boot. Mirrors
# `virsh net-autostart`.
#
# Globals:
#   None.
# Arguments:
#   $1   Network name to mark autostart.
# Outputs:
#   Whatever `virsh net-autostart` writes.
# Returns:
#   The exit status of `virsh net-autostart`.
virsh::net_autostart() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return 1
  virsh net-autostart "$1"
}

# virsh::net_parse_info(network search)
#
# Greps `virsh net-info`'s output for the given field name and returns 0
# if its value is "yes".
#
# Globals:
#   __BASHKIT_VIRSH_NETWORK_KEY_ACTIVE, __BASHKIT_VIRSH_NETWORK_KEY_PERSISTENT, __BASHKIT_VIRSH_NETWORK_KEY_AUTOSTART
# Arguments:
#   $1   Network name.
#   $2   Field name to search for; must be one of the __NETWORK_KEY_*
#        constants.
# Outputs:
#   An error if $2 is not a recognized field name.
# Returns:
#   1 if $2 is unrecognized; otherwise 0 if the field's value is "yes",
#   non-zero otherwise.
virsh::net_parse_info() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 2 "$@" || return 1
  local -r network="$1"
  local -r search="$2"

  local regex_test="${__BASHKIT_VIRSH_NETWORK_KEY_ACTIVE}"
  regex_test+="|${__BASHKIT_VIRSH_NETWORK_KEY_PERSISTENT}"
  regex_test+="|${__BASHKIT_VIRSH_NETWORK_KEY_AUTOSTART}"
  readonly regex_test

  if ! [[ "${search}" =~ ${regex_test} ]]; then
    log_error "\$1 failed regex match: ${regex_test}"
    return 1
  fi

  virsh net-info "${network}" \
    | grep "${search}" \
    | tr -d ' ' \
    | cut -d : -f 2 \
    | grep -q "$BOOLEAN_YES"
}
