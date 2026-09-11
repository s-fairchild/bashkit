# shellcheck shell=bash
#
# Umbrella loader for bashkit/local/lib/bashkit/k3s library files.

readonly __BASHKIT_LIB_K3S_SOURCED="true"

if [[ "${__BASHKIT_LIB_K3S_TOKEN_UTILS_SOURCED:-}" != "true" ]]; then
  # shellcheck source=token-utils.sh
  . "${BASH_SOURCE[0]%/*}/token-utils.sh"
fi
