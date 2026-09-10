# hack/lib/podman/podman.sh
#
# Umbrella loader for the podman-container/podman-secret/podman-volume library files.
# shellcheck shell=bash

readonly __LIB_PODMAN_SOURCED="true"

if [[ "${__BASHKIT_LIB_PODMAN_CONTAINER_SOURCED:-}" != "true" ]]; then
  # shellcheck source=podman-container.sh
  . "${BASH_SOURCE[0]%/*}/podman-container.sh"
fi

if [[ "${__BASHKIT_LIB_PODMAN_SECRET_SOURCED:-}" != "true" ]]; then
  # shellcheck source=podman-secret.sh
  . "${BASH_SOURCE[0]%/*}/podman-secret.sh"
fi

if [[ "${__BASHKIT_LIB_PODMAN_VOLUME_SOURCED:-}" != "true" ]]; then
  # shellcheck source=podman-volume.sh
  . "${BASH_SOURCE[0]%/*}/podman-volume.sh"
fi
