# shellcheck shell=bash
#
# Umbrella loader for bashkit/local/lib/bashkit/virsh library files.
#
# Add new core library files to this file as they are created.

readonly __BASHKIT_LIB_VIRSH_SOURCED="true"

if [[ "${__BASHKIT_LIB_VIRSH_DOMAIN_SOURCED:-}" ]]; then
  # shellcheck source=virsh-domain.sh
  . "${BASH_SOURCE[0]%/*}/virsh-domain.sh"
fi

if [[ "${__BASHKIT_LIB_VIRSH_NETWORK_SOURCED:-}" != "true" ]]; then
  # shellcheck source=virsh-network.sh
  . "${BASH_SOURCE[0]%/*}/virsh-network.sh"
fi

if [[ "${__BASHKIT_LIB_VIRSH_POOL_SOURCED:-}" != "true" ]]; then
  # shellcheck source=virsh-pool.sh
  . "${BASH_SOURCE[0]%/*}/virsh-pool.sh"
fi
