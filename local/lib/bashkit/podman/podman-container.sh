# hack/lib/podman/podman-container.sh
#
# Runs a nested `podman` CLI inside a container, with the host's rootless podman
# graphroot volume mounted so the nested podman shares its storage.
# shellcheck shell=bash

[[ "${XTRACE:-0}" -eq 1 ]] && set -x

readonly __BASHKIT_LIB_PODMAN_CONTAINER_SOURCED="true"

readonly __BASHKIT_LIB_PODMAN_CONTAINER_USER="podman"
readonly __BASHKIT_LIB_PODMAN_CONTAINER_VOLUME_GRAPHROOT_USER_PODMAN="graphroot-user-podman"
readonly __BASHKIT_LIB_PODMAN_CONTAINER_VOLUME_TARGET_GRAPHROOT_USER_PODMAN="/home/podman/.local/share/containers/storage"

# podman::container(args...)
#
# Runs `podman <args...>` inside a registry.redhat.io/ubi10/podman container, with the
# graphroot-user-podman volume mounted so the nested podman shares the host's rootless
# podman storage.
#
# Arguments:
#   $@   Arguments passed through verbatim to the containerized `podman` CLI.
# Outputs:
#   Writes the nested podman invocation's stdout/stderr.
# Returns:
#   The nested podman invocation's exit status.
podman::container() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  local volume="${__BASHKIT_LIB_PODMAN_CONTAINER_VOLUME_GRAPHROOT_USER_PODMAN}"
  volume+=":${__BASHKIT_LIB_PODMAN_CONTAINER_VOLUME_TARGET_GRAPHROOT_USER_PODMAN}"
  volume+=":Z"

  local -a podman_options=(
    "--rm"
    "-i"
    "--user=${__BASHKIT_LIB_PODMAN_CONTAINER_USER}"
    "--security-opt=label=disable"
    "--volume=${volume}"
  )
  local -r image="registry.redhat.io/ubi10/podman:latest"

  podman run \
    "${podman_options[@]}" \
    "${image}" \
    podman \
    "$@"
}

if [[ "${__BASHKIT_LIB_CORE_CONTRACT_UTILS_SOURCED:-}" != "true" ]]; then
  # shellcheck source=../core/contract-utils.sh
  . "${BASH_SOURCE[0]%/*}/../core/contract-utils.sh"
fi
