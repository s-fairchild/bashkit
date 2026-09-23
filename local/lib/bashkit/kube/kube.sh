# shellcheck shell=bash

[[ "${XTRACE:-0}" -eq 1 ]] && set -x

readonly __BASHKIT_LIB_KUBE_SOURCED="true"

if [[ "${__BASHKIT_LIB_KUBE_KUBECTL_SOURCED:-}" != "true" ]]; then
  # shellcheck source=kubectl.sh
  . "${BASH_SOURCE[0]%/*}/kubectl.sh"
fi

if [[ "${__BASHKIT_LIB_KUBE_KUSTOMIZE_SOURCED:-}" != "true" ]]; then
  # shellcheck source=kustomize.sh
  . "${BASH_SOURCE[0]%/*}/kustomize.sh"
fi
