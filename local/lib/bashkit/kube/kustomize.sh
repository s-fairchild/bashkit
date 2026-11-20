# shellcheck shell=bash
#
# kustomize wrappers: kube::kustomize_build renders a kustomization to
# stdout, and kube::kustomize_build_apply applies the result with
# kube::kubectl_apply.

readonly __BASHKIT_LIB_KUBE_KUSTOMIZE_SOURCED="true"

# kube::kustomize_build(kustomize_dir)
#
# Runs `kustomize build <kustomize_dir>` and writes the rendered manifests to
# stdout. kustomize's stderr is left on stderr, so its warnings can't end up
# in the manifests a caller parses.
#
# Globals:
#   None.
# Arguments:
#   $1   The kustomization directory.
# Outputs:
#   An info line with the command. The rendered manifests on stdout, and
#   kustomize's warnings and errors on stderr. An error and stack trace if
#   <kustomize_dir> is missing or isn't a directory.
# Returns:
#   1 if <kustomize_dir> is missing or isn't a directory; kustomize's exit
#   status otherwise.
kube::kustomize_build() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  core::require_operands 1 "$@" || return
  local -r kustomize_dir="${1}"

  if ! [[ -d "${kustomize_dir}" ]]; then
    core::fail "directory not found: ${kustomize_dir}" || return
  fi

  local -a _cmd=(
    "kustomize"
    "build"
    "${kustomize_dir}"
  )

  log_info "${_cmd[*]}"
  # Don't add 2>&1: it would mix kustomize's warnings (deprecated fields and
  # so on) into the manifests that callers pipe to kubectl or yq.
  "${_cmd[@]}"
}

# kube::kustomize_build_apply(kustomize_dir)
#
# Builds <kustomize_dir> with kube::kustomize_build and pipes the manifests
# to kube::kubectl_apply, which reads them from stdin.
#
# Globals:
#   None.
# Arguments:
#   $1   The kustomization directory.
# Outputs:
#   See kube::kustomize_build and kube::kubectl_apply. An error and stack
#   trace if either stage fails.
# Returns:
#   1 if either stage fails; 0 otherwise.
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
