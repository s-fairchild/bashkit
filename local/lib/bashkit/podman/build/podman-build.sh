# hack/lib/podman/podman.sh
#
# Umbrella loader for the podman/build library files.
# shellcheck shell=bash

readonly __LIB_PODMAN_BUILD_SOURCED="true"

if [[ "${__BASHKIT_LIB_PODMAN_BUILD_MULTI_STAGE_SOURCED:-}" != "true" ]]; then
  # shellcheck source=build-multi-stage.sh
  . "${BASH_SOURCE[0]%/*}/build-multi-stage.sh"
fi
