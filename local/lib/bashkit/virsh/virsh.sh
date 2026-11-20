# shellcheck shell=bash
#
# Umbrella loader for bashkit/local/lib/bashkit/virsh library files.
#
# Add new core library files to this file as they are created.

# shellcheck source=virsh-domain.sh
. /dev/null
import virsh/virsh-domain.sh

# shellcheck source=virsh-network.sh
. /dev/null
import virsh/virsh-network.sh

# shellcheck source=virsh-pool.sh
. /dev/null
import virsh/virsh-pool.sh
