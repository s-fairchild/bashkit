# shellcheck shell=bash

readonly __BASHKIT_LIB_KUBE_KUBECTL_SOURCED="true"

# kube::kubectl_wait(resource [namespace] [timeout])
#
# Runs `kubectl wait --for=condition=Available` on <resource> and logs what
# it is waiting for.
#
# Globals:
#   None.
# Arguments:
#   $1   The resource, e.g. deployment/virt-operator.
#   $2   Optional. The namespace. Defaults to kubectl's current namespace.
#   $3   Optional. The timeout, in kubectl's duration format. Defaults to
#        300s.
# Outputs:
#   An info line before waiting, whatever `kubectl wait` writes, and an error
#   and stack trace if <resource> doesn't become Available in time.
# Returns:
#   1 if <resource> is missing or doesn't become Available in time; 0
#   otherwise.
kube::kubectl_wait() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return
  local -r resource="${1}"
  local -r namespace="${2:-}"
  local -r timeout="${3:-300s}"
  local -r condition="${4:-Available}"

  local msg="Waiting for ${resource}"
  [[ -n "${namespace}" ]] && msg+=" in namespace ${namespace}"
  msg+=" to become ${condition} (timeout ${timeout})."
  readonly msg
  log_info "${msg}"

  local -ar _cmd=(
    "kubectl"
    "wait"
    "${resource}"
    "-n"
    "${namespace}"
    --for=condition="${condition}"
    --timeout="${timeout}"
  )
  log_info "${_cmd[*]}"

  local -a _cmd_logs
  _cmd_logs=("$("${_cmd[@]}" 2>&1)") || return
  readonly _cmd_logs

  local line
  for line in "${_cmd_logs[@]}"; do
    log_info "${line}"
  done
}

#######################################
# Description:
#   Runs `kubectl <operation> -f <file> [args...]`. Shared implementation
#   behind kube::kubectl_apply/create/delete.
# Globals:
#   None
# Arguments:
#   $1 - kubectl operation: apply, create, or delete
#   $2 - manifest file (optional, defaults to "-" for stdin; must not be empty)
#   $@ - remaining args forwarded to kubectl (e.g. -n ns, --ignore-not-found)
# Outputs:
#   kubectl output to stdout/stderr; error log on failure
# Returns:
#   0 on success, 1 on invalid operands or kubectl failure
#######################################
kube::kubectl_file_op() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  core::require_operands 1 "$@" || return
  local -r operation="${1}"
  shift

  case "${operation}" in
    apply|create|delete) ;;
    *) core::fail "unsupported operation: ${operation}"; return ;;
  esac

  local file="-"
  if (( $# > 0 )); then
    file="${1:-}"
    shift

    [[ -n "${file}" ]] || { core::fail "file operand is empty" || return; }
  fi
  readonly file
  log_debug "$(declare -p file)"

  local -ar _cmd=(
    "kubectl"
    "${operation}"
    "-f"
    "${file}"
  )
  log_info "${_cmd[*]}"

  local _cmd_logs
  _cmd_logs="$("${_cmd[@]}" 2>&1)" || return
  readonly _cmd_logs

  local line
  for line in "${_cmd_logs[@]}"; do
    log_info "${line}"
  done
}

#######################################
# Description:
#   kubectl apply -f <file|stdin> [args...]
# Arguments:
#   See kube::kubectl_file_op ($2 onward)
# Returns:
#   0 on success, 1 on failure
#######################################
kube::kubectl_apply() { kube::kubectl_file_op apply "$@" || return; }

#######################################
# Description:
#   kubectl create -f <file|stdin> [args...]
# Arguments:
#   See kube::kubectl_file_op ($2 onward)
# Returns:
#   0 on success, 1 on failure
#######################################
kube::kubectl_create() { kube::kubectl_file_op create "$@" || return; }

#######################################
# Description:
#   kubectl delete -f <file|stdin> [args...]
# Arguments:
#   See kube::kubectl_file_op ($2 onward)
# Returns:
#   0 on success, 1 on failure
#######################################
kube::kubectl_delete() { kube::kubectl_file_op delete "$@" || return; }


if [[ "${__BASHKIT_CORE_CONTRACT_UTILS_SOURCED:-}" != "true" ]]; then
  # shellcheck source=../core/contract-utils.sh
  . "${BASH_SOURCE[0]%/*}/../core/contract-utils.sh"
fi
