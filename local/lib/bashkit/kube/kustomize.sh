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

  # shellcheck disable=SC2119
  kube::kustomize_build "$@" | kube::kubectl_apply
  core::require_pipestatus "${PIPESTATUS[@]}" || return
}

if ! declare -f init_logger >/dev/null 2>&1; then
  # logging.sh should already be sourced by now.
  # This is primarily present to provide shellcheck function definitions.
  #
  # shellcheck source=../../../../../bash-logger/logging.sh
  . "${BASH_SOURCE[0]%/*}/../../../../../bash-logger/logging.sh"

  init_logger --name "$(basename "${0}")"
fi

if [[ "${__BASHKIT_LIB_CORE_CONTRACT_UTILS_SOURCED:-}" != "true" ]]; then
  # shellcheck source=../core/contract-utils.sh
  . "${BASH_SOURCE[0]%/*}/../core/contract-utils.sh"
fi

if [[ "${__BASHKIT_LIB_KUBE_KUBECTL_SOURCED:-}" != "true" ]]; then
  # shellcheck source=kubectl.sh
  . "${BASH_SOURCE[0]%/*}/kubectl.sh"
fi
