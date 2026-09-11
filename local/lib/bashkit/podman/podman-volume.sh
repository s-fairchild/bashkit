# hack/lib/podman/podman-volume.sh
#
# shellcheck shell=bash

[[ "${XTRACE:-0}" -eq 1 ]] && set -x

readonly __BASHKIT_LIB_PODMAN_VOLUME_SOURCED="true"

# podman::volume_exists(name)
#
# Returns 0 if a podman volume with the given name exists, non-zero otherwise.
#
# Arguments:
#   $1   Podman volume name to check.
# Returns:
#   0 if the volume exists; 1 otherwise (also logs an error).
podman::volume_exists() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  core::require_operands 1 "$@" || return 1
  local -r v="$1"

  if ! podman volume exists "${v}"; then
    log_error "podman volume ${v} not found."
    return 1
  fi
}

# podman::volume_create(name)
#
# Creates a podman volume if it doesn't already exist, labeled with the current
# working directory's basename as its project.
#
# Arguments:
#   $1   Podman volume name to create.
# Outputs:
#   Warns to stderr if the volume already exists (does not replace it).
# Returns:
#   Non-zero (via fatal) if volume creation fails.
podman::volume_create() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  core::require_operands 1 "$@" || return 1
  local -r v="$1"

  # Possible nice to have features here
  #   * populate label overlay
  #   * populate bootstrap with butane or ignition
  #   * accept array of labels to apply, expand them with --label prefixing each string
  if podman volume exists "${v}"; then
    log_warn "podman volume already exists. Refusing to replace." \
      "Manually delete this volume and re-run."
  else
    podman volume \
      create \
      --ignore \
      --label project="$(basename "${PWD}")" \
      "${v}" \
      || log_fatal "Failed to create podman volume: ${v}"
  fi
}

# podman::volume_export_untar_stdout(name target)
#
# Exports a podman volume as a tar stream and extracts a single target path from it
# to stdout, without ever writing the volume's tar archive to disk.
#
# Arguments:
#   $1   Podman volume name to export.
#   $2   Path within the volume's tar archive to extract.
# Outputs:
#   Writes the extracted target's raw contents to stdout.
podman::volume_export_untar_stdout() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 2 "$@" || return 1
  local -r vol="$1"
  local -r target="$2"

  log_info "Extracting ${target} to stdout from podman volume ${vol}."
  podman volume \
    export \
    "${vol}" \
    | tar x "${target}" -O
}

if [[ "${__BASHKIT_LIB_CORE_CONTRACT_UTILS_SOURCED:-}" != "true" ]]; then
  # shellcheck source=../core/contract-utils.sh
  . "${BASH_SOURCE[0]%/*}/../core/contract-utils.sh"
fi
