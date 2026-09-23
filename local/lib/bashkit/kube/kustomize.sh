# shellcheck shell=bash

[[ "${XTRACE:-0}" -eq 1 ]] && set -x

readonly __BASHKIT_LIB_KUBE_KUSTOMIZE_SOURCED="true"

kube::kustomize_build() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  core::require_operands 1 "$@" || return
  local -r kustomize_dir="${1}"

  [[ -d "${kustomize_dir}" ]] || { core::fail "directory not found: ${kustomize_dir}" || return; }

  local -a cmd=(
    "kustomize"
    "build"
    "${kustomize_dir}"
  )

  log_info "${cmd[*]}"
  # shellcheck disable=SC2068
  ${cmd[@]}
}

kube::kustomize_build_apply() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  # kube::kubectl_apply positional args are optional.
  # shellcheck disable=SC2119
  #
  # PIPESTATUS is checked by core::require_pipestatus below.
  # shellcheck disable=SC2312
  kube::kustomize_build "$@" | kube::kubectl_apply
  core::require_pipestatus "${PIPESTATUS[@]}" || return
}

if [[ "${__BASHKIT_CORE_CONTRACT_UTILS_SOURCED:-}" != "true" ]]; then
  # shellcheck source=../core/contract-utils.sh
  . "${BASH_SOURCE[0]%/*}/../core/contract-utils.sh"
fi

if [[ "${__BASHKIT_LIB_KUBE_KUBECTL_SOURCED:-}" != "true" ]]; then
  # shellcheck source=kubectl.sh
  . "${BASH_SOURCE[0]%/*}/kubectl.sh"
fi
