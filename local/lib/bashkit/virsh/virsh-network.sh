# shellcheck shell=bash
#
# Thin, operand-validated wrappers around `virsh` network subcommands.

declare -r __vendor_bashkit_lib_virsh_network_sourced="true"

declare -r __NETWORK_KEY_ACTIVE="Active"
declare -r __NETWORK_KEY_PERSISTENT="Persistent"
declare -r __NETWORK_KEY_AUTOSTART="Autostart"

# virsh_net_define(name [description])
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
virsh_net_define() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

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

# virsh_net_activate(name)
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
virsh_net_activate() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return 1
  virsh net-start "$1"
}

# virsh_net_destroy(name)
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
virsh_net_destroy() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return 1
  virsh net-destroy "$1"
}

# virsh_net_is_defined(name)
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
virsh_net_is_defined() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return 1
  virsh net-uuid "$1" > /dev/null 2>&1
}

# virsh_net_is_active(name)
#
# Returns 0 if the network is currently active, non-zero otherwise. Thin
# wrapper around `virsh net-info` for use in conditional expressions.
#
# Globals:
#   __NETWORK_KEY_ACTIVE
# Arguments:
#   $1   Network name to check.
# Outputs:
#   None.
# Returns:
#   0 if the network's "Active" field is "yes"; non-zero otherwise.
virsh_net_is_active() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return 1
  virsh_net_parse_info "$1" "${__NETWORK_KEY_ACTIVE}"
}

# virsh_net_is_persistent(name)
#
# Returns 0 if the network has a persistent definition, non-zero
# otherwise. Thin wrapper around `virsh net-info` for use in conditional
# expressions.
#
# Globals:
#   __NETWORK_KEY_PERSISTENT
# Arguments:
#   $1   Network name to check.
# Outputs:
#   None.
# Returns:
#   0 if the network's "Persistent" field is "yes"; non-zero otherwise.
virsh_net_is_persistent() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return 1
  virsh_net_parse_info "$1" "${__NETWORK_KEY_PERSISTENT}"
}

# virsh_net_is_autostart(name)
#
# Returns 0 if the network is marked to autostart, non-zero otherwise.
# Thin wrapper around `virsh net-info` for use in conditional expressions.
#
# Globals:
#   __NETWORK_KEY_AUTOSTART
# Arguments:
#   $1   Network name to check.
# Outputs:
#   None.
# Returns:
#   0 if the network's "Autostart" field is "yes"; non-zero otherwise.
virsh_net_is_autostart() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return 1
  virsh_net_parse_info "$1" "${__NETWORK_KEY_AUTOSTART}"
}

# virsh_net_autostart(name)
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
virsh_net_autostart() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return 1
  virsh net-autostart "$1"
}

# virsh_net_parse_info(network search)
#
# Greps `virsh net-info`'s output for the given field name and returns 0
# if its value is "yes".
#
# Globals:
#   __NETWORK_KEY_ACTIVE, __NETWORK_KEY_PERSISTENT, __NETWORK_KEY_AUTOSTART
# Arguments:
#   $1   Network name.
#   $2   Field name to search for; must be one of the __NETWORK_KEY_*
#        constants.
# Outputs:
#   An error if $2 is not a recognized field name.
# Returns:
#   1 if $2 is unrecognized; otherwise 0 if the field's value is "yes",
#   non-zero otherwise.
virsh_net_parse_info() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 2 "$@" || return 1
  local -r network="$1"
  local -r search="$2"

  local -r regex_test="(${__NETWORK_KEY_ACTIVE}|${__NETWORK_KEY_PERSISTENT}|${__NETWORK_KEY_AUTOSTART})"
  if ! [[ "${search}" =~ ${regex_test} ]]; then
    error "\$1 ${ERROR_REGEX_FAIL}: ${regex_test}"
    return 1
  fi

  virsh net-info "${network}" \
    | grep "${search}" \
    | tr -d ' ' \
    | cut -d : -f 2 \
    | grep -q "yes"
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
