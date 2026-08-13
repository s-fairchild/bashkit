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

    require_operands 1 "$@" || return 1
    virsh pool-define "$1"
}

# virsh_pool_build()
#
# Creates the on-disk target directory for a defined pool. Mirrors `virsh pool-build`.
# For fs/disk/logical pools -- the only types --overwrite/--no-overwrite are valid
# for (virsh(1)) -- passes --no-overwrite so an already-built pool is left untouched
# instead of erroring. Any other pool type (e.g. dir) is built with no flags: those
# flags fail on such pools with "No source device specified when formatting pool",
# and an unflagged build is already idempotent for them (a dir pool build is just
# `mkdir -p` on the target path).
#
# args:
#   * 1) name - string; pool name to build.
virsh_pool_build() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    require_operands 1 "$@" || return 1
    local -r name="$1"

    local pool_type
    pool_type="$(virsh pool-dumpxml "$name" | grep -oP "(?<=<pool type=')[^']+")"

    case "$pool_type" in
        fs | disk | logical) virsh pool-build "$name" --no-overwrite ;;
        *)                    virsh pool-build "$name" ;;
    esac
}

# virsh_pool_start()
#
# Starts (activates) a defined storage pool. Mirrors `virsh pool-start`.
#
# args:
#   * 1) name - string; pool name to start.
virsh_pool_start() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    require_operands 1 "$@" || return 1

    virsh pool-start "$1"
}

# virsh_pool_autostart()
#
# Marks a defined storage pool to autostart on host boot. Mirrors `virsh pool-autostart`.
#
# args:
#   * 1) name - string; pool name to mark autostart.
virsh_pool_autostart() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    require_operands 1 "$@" || return 1

    virsh pool-autostart "$1"
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
    require_operands 1 "$@" || return 1

    virsh pool-uuid "$1" > /dev/null 2>&1
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
    require_operands 1 "$@" || return 1

    # Capture first, then grep the captured text (not a live pipe): under this
    # repo's `set -o pipefail`, `virsh pool-info | grep -q ...` intermittently
    # fails the whole pipeline even on a match -- grep -q exits the instant it
    # matches "State: running" (line 3 of ~8), SIGPIPEing virsh before it finishes
    # writing the remaining lines, and pipefail reports that SIGPIPE exit (141)
    # instead of grep's own success.
    local info
    info="$(virsh pool-info "$1" 2> /dev/null)"
    grep -q '^State: *running' <<< "$info"
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

    require_operands 2 "$@" || return 1
    local -r pool="$1"
    local -r xml_file="$2"

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

    require_operands 2 "$@" || return 1
    local -r pool="$1"
    local -r vol="$2"

    virsh vol-info \
          --pool "$pool" \
          "$vol" \
          > /dev/null 2>&1
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
