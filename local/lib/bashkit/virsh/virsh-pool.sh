# shellcheck shell=bash
#
# Thin, operand-validated wrappers around `virsh` storage pool/volume
# subcommands.

declare -r __vendor_bashkit_lib_virsh_pool_sourced="true"

# virsh_pool_define(xml_file)
#
# Persistently defines a storage pool from an XML file (or "/dev/stdin").
# Mirrors `virsh pool-define`. The pool's target directory is not created
# by this call -- see virsh_pool_build().
#
# Globals:
#   None.
# Arguments:
#   $1   Path to a storage pool XML file, or "/dev/stdin".
# Outputs:
#   Whatever `virsh pool-define` writes.
# Returns:
#   The exit status of `virsh pool-define`.
virsh_pool_define() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return 1
  virsh pool-define "$1"
}

# virsh_pool_build(name)
#
# Creates the on-disk target directory for a defined pool. Mirrors
# `virsh pool-build`. For fs/disk/logical pools -- the only types
# --overwrite/--no-overwrite are valid for (virsh(1)) -- passes
# --no-overwrite so an already-built pool is left untouched instead of
# erroring. Any other pool type (e.g. dir) is built with no flags: those
# flags fail on such pools with "No source device specified when
# formatting pool", and an unflagged build is already idempotent for them
# (a dir pool build is just `mkdir -p` on the target path).
#
# Globals:
#   None.
# Arguments:
#   $1   Pool name to build.
# Outputs:
#   Whatever `virsh pool-build` writes.
# Returns:
#   The exit status of `virsh pool-build`.
virsh_pool_build() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return 1
  local -r name="$1"

  local pool_type
  pool_type="$(virsh pool-dumpxml "${name}" | grep -oP "(?<=<pool type=')[^']+")"

  case "${pool_type}" in
    fs | disk | logical) virsh pool-build "${name}" --no-overwrite ;;
    *)                    virsh pool-build "${name}" ;;
  esac
}

# virsh_pool_start(name)
#
# Starts (activates) a defined storage pool. Mirrors `virsh pool-start`.
#
# Globals:
#   None.
# Arguments:
#   $1   Pool name to start.
# Outputs:
#   Whatever `virsh pool-start` writes.
# Returns:
#   The exit status of `virsh pool-start`.
virsh_pool_start() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  core::require_operands 1 "$@" || return 1

  virsh pool-start "$1"
}

# virsh_pool_autostart(name)
#
# Marks a defined storage pool to autostart on host boot. Mirrors
# `virsh pool-autostart`.
#
# Globals:
#   None.
# Arguments:
#   $1   Pool name to mark autostart.
# Outputs:
#   Whatever `virsh pool-autostart` writes.
# Returns:
#   The exit status of `virsh pool-autostart`.
virsh_pool_autostart() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  core::require_operands 1 "$@" || return 1

  virsh pool-autostart "$1"
}

# virsh_pool_is_defined(name)
#
# Returns 0 if a storage pool with the given name has a persistent
# definition, non-zero otherwise. Thin wrapper around `virsh pool-uuid`
# for use in conditional expressions.
#
# Globals:
#   None.
# Arguments:
#   $1   Pool name to check.
# Outputs:
#   None.
# Returns:
#   0 if the pool is defined; non-zero otherwise.
virsh_pool_is_defined() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  core::require_operands 1 "$@" || return 1

  virsh pool-uuid "$1" > /dev/null 2>&1
}

# virsh_pool_is_active(name)
#
# Returns 0 if the storage pool is currently running, non-zero otherwise.
# Thin wrapper around `virsh pool-info` for use in conditional
# expressions.
#
# Globals:
#   None.
# Arguments:
#   $1   Pool name to check.
# Outputs:
#   None.
# Returns:
#   0 if the pool's state is "running"; non-zero otherwise.
virsh_pool_is_active() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  core::require_operands 1 "$@" || return 1

  # Capture first, then grep the captured text (not a live pipe): under
  # this repo's `set -o pipefail`, `virsh pool-info | grep -q ...`
  # intermittently fails the whole pipeline even on a match -- grep -q
  # exits the instant it matches "State: running" (line 3 of ~8),
  # SIGPIPEing virsh before it finishes writing the remaining lines, and
  # pipefail reports that SIGPIPE exit (141) instead of grep's own
  # success.
  local info
  info="$(virsh pool-info "$1" 2> /dev/null)"
  grep -q '^State: *running' <<< "${info}"
}

# virsh_vol_create(pool xml_file)
#
# Creates a storage volume within a pool from an XML file (or
# "/dev/stdin"). Mirrors `virsh vol-create`. The pool must already be
# defined and active.
#
# Globals:
#   None.
# Arguments:
#   $1   Name of the pool to create the volume in.
#   $2   Path to a storage volume XML file, or "/dev/stdin".
# Outputs:
#   Whatever `virsh vol-create` writes.
# Returns:
#   The exit status of `virsh vol-create`.
virsh_vol_create() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 2 "$@" || return 1
  local -r pool="$1"
  local -r xml_file="$2"

  virsh vol-create "${pool}" "${xml_file}"
}

# virsh_vol_is_present(pool vol)
#
# Returns 0 if a volume with the given name exists within the given pool,
# non-zero otherwise. Thin wrapper around `virsh vol-info` for use in
# conditional expressions.
#
# Globals:
#   None.
# Arguments:
#   $1   Name of the pool to check.
#   $2   Volume name to check for.
# Outputs:
#   None.
# Returns:
#   0 if the volume exists; non-zero otherwise.
virsh_vol_is_present() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 2 "$@" || return 1
  local -r pool="$1"
  local -r vol="$2"

  virsh vol-info \
    --pool "${pool}" \
    "${vol}" \
    > /dev/null 2>&1
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
