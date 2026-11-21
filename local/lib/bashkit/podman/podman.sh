# shellcheck shell=bash
#
# Umbrella loader for bashkit/local/lib/bashkit/podman library files.

# shellcheck source=podman-container.sh
. /dev/null
import podman/podman-container.sh

# shellcheck source=podman-secret.sh
. /dev/null
import podman/podman-secret.sh

# shellcheck source=podman-volume.sh
. /dev/null
import podman/podman-volume.sh
