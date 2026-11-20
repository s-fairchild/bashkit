# shellcheck shell=bash
#
# kubectl wrappers: kube::kubectl_wait, and kube::kubectl_apply,
# kube::kubectl_create and kube::kubectl_delete on top of
# kube::kubectl_file_op. Each logs the command it runs and passes kubectl's
# output on through the logger.

readonly __BASHKIT_LIB_KUBE_KUBECTL_SOURCED="true"

# kube::kubectl(args...)
#
# Runs the kubectl binary found on PATH, skipping any shell function named
# kubectl (including the one below).
#
# Globals:
#   None.
# Arguments:
#   $@   Passed to kubectl unchanged.
# Outputs:
#   Whatever kubectl writes.
# Returns:
#   kubectl's exit status.
kube::kubectl() { command kubectl "$@"; }

# kubectl(args...)
#
# Replaces the kubectl command in every shell that sources this file, so a
# bare `kubectl` runs kube::kubectl.
#
# Globals:
#   None.
# Arguments:
#   $@   Passed to kube::kubectl unchanged.
# Outputs:
#   Whatever kubectl writes.
# Returns:
#   kubectl's exit status.
kubectl() { kube::kubectl "$@"; }

# kube::kubectl_wait(-r resource [-n namespace] [-t timeout] [-c condition])
#
# Runs `kubectl wait --for=condition=<condition> --timeout=<timeout>
# <resource>`. Logs the command and what it is waiting for, then kubectl's
# combined stdout and stderr: at INFO level if the wait succeeds, at ERROR
# level if it fails.
#
# Globals:
#   None.
# Arguments:
#   -r resource    The resource, e.g. deployment/virt-operator. Required.
#   -n namespace   Optional. Passed to kubectl as `-n <namespace>`. Defaults
#                  to kubectl's current namespace.
#   -t timeout     Optional. The timeout, in kubectl's duration format.
#                  Defaults to 300s.
#   -c condition   Optional. The condition to wait for. Defaults to
#                  Available.
# Outputs:
#   Info lines with the command and what it waits for, then kubectl's
#   output. An error and stack trace on a bad option or a missing -r.
# Returns:
#   1 on a bad option, a missing -r, or a failed wait (including a timeout);
#   0 otherwise.
kube::kubectl_wait() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  local resource="" namespace="" timeout="300s" condition="--for=condition=Available"
  local -a _cmd=("kubectl" "wait")
  local -i OPTIND=1
  while getopts ':r:n:t:c:' opt; do
    case "${opt}" in
      r)
        if ! core::is_option_arg_dup "${opt}" "${resource}"; then
          core::fail || return
        fi
        resource="${OPTARG}"
        ;;
      n)
        if ! core::is_option_arg_dup "${opt}" "${namespace}"; then
          core::fail || return
        fi
        namespace="${OPTARG}"
        ;;
      t) timeout="${OPTARG}"; ;;
      c) condition="${OPTARG}"; ;;
      :)
        core::fail "$(basename "${0}") -${OPTARG} operand must be provided." \
          || return
        ;;
      ?)
        core::fail "$(basename "${0}") -${OPTARG} option is unknown." \
          || return
        ;;
    esac
  done
  shift $((OPTIND - 1))
  readonly resource namespace timeout condition
  log_debug "$(declare -p resource namespace timeout condition)"

  if [[ -z "${resource}" ]]; then
    core::fail "${FUNCNAME[0]}(-r resource) operand is required." \
      || return
  fi
  if [[ -n "${namespace}" ]]; then
    _cmd+=("-n" "${namespace}")
  fi

  _cmd+=(
    "${condition}"
    "--timeout=${timeout}"
    "${resource}"
  )

  readonly _cmd
  log_info "${_cmd[*]}"

  local msg_prefix="Waiting for ${resource}"
  [[ -z "${namespace}" ]] || msg_prefix+=" in namespace ${namespace}"
  log_info "${msg_prefix} to become ${condition} (timeout ${timeout})."

  local -a _cmd_logs
  local level="info"
  if ! _cmd_logs=("$("${_cmd[@]}" 2>&1)"); then
    level="error"
  fi
  readonly _cmd_logs level

  local line
  for line in "${_cmd_logs[@]}"; do
    "log_${level}" "${line}"
  done

  [[ "${level}" != "error" ]] || return 1
}

# kube::kubectl_file_op(operation [file [kubectl_args...]])
#
# Runs `kubectl <operation> -f <file> [kubectl_args...]`, the shared
# implementation behind kube::kubectl_apply, kube::kubectl_create and
# kube::kubectl_delete. Logs the command, then kubectl's combined stdout and
# stderr: at INFO level if kubectl succeeds, at ERROR level if it fails.
#
# Globals:
#   None.
# Arguments:
#   $1   The kubectl operation: apply, create or delete.
#   $2   Optional. The manifest file or directory, or "-" for stdin.
#        Defaults to "-" when omitted; must not be empty when given.
#   $@   Optional. Further arguments for kubectl, placed after <file>, e.g.
#        `-n <namespace>` or --ignore-not-found.
# Outputs:
#   An info line with the command, then kubectl's output. An error and stack
#   trace on an unsupported <operation> or an empty <file>.
# Returns:
#   1 on an invalid operand or if kubectl fails; 0 otherwise.
kube::kubectl_file_op() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  core::require_operands 1 "$@" || return
  local -r operation="${1}"
  shift; log_debug "$(declare -p operation)"

  case "${operation}" in
    apply|create|delete) ;;
    *) core::fail "unsupported operation: ${operation}"; return ;;
  esac

  local file="-"
  if (( $# > 0 )); then
    file="${1:-}"
    shift

    [[ -n "${file}" ]] || {
      core::fail "file operand is empty" || return
    }
  fi
  readonly file
  log_debug "$(declare -p file)"

  local -a _cmd=(
    "kubectl"
    "${operation}"
    "-f"
    "${file}"
  )
  if (( $# > 0 )); then
    log_debug "Inserting extra arguments into _cmd: $*"
    _cmd+=("$@")
  fi
  readonly _cmd
  log_info "${_cmd[*]}"

  local -a _cmd_logs
  local level="info"
  if ! _cmd_logs=("$("${_cmd[@]}" 2>&1)"); then
    level="error"
  fi
  readonly _cmd_logs level

  local line
  for line in "${_cmd_logs[@]}"; do
    "log_${level}" "${line}"
  done

  [[ "${level}" != "error" ]] || return 1
}

# kube::kubectl_apply([file [kubectl_args...]])
#
# Runs `kubectl apply -f <file> [kubectl_args...]` through
# kube::kubectl_file_op. <file> defaults to "-" (stdin).
#
# Globals:
#   None.
# Arguments:
#   $@   See kube::kubectl_file_op, from $2 on.
# Outputs:
#   See kube::kubectl_file_op.
# Returns:
#   kube::kubectl_file_op's exit status.
kube::kubectl_apply() { kube::kubectl_file_op apply "$@" || return; }

# kube::kubectl_create([file [kubectl_args...]])
#
# Runs `kubectl create -f <file> [kubectl_args...]` through
# kube::kubectl_file_op. <file> defaults to "-" (stdin).
#
# Globals:
#   None.
# Arguments:
#   $@   See kube::kubectl_file_op, from $2 on.
# Outputs:
#   See kube::kubectl_file_op.
# Returns:
#   kube::kubectl_file_op's exit status.
kube::kubectl_create() { kube::kubectl_file_op create "$@" || return; }

# kube::kubectl_delete([file [kubectl_args...]])
#
# Runs `kubectl delete -f <file> [kubectl_args...]` through
# kube::kubectl_file_op. <file> defaults to "-" (stdin).
#
# Globals:
#   None.
# Arguments:
#   $@   See kube::kubectl_file_op, from $2 on.
# Outputs:
#   See kube::kubectl_file_op.
# Returns:
#   kube::kubectl_file_op's exit status.
kube::kubectl_delete() { kube::kubectl_file_op delete "$@" || return; }


if [[ "${__BASHKIT_CORE_CONTRACT_UTILS_SOURCED:-}" != "true" ]]; then
  # shellcheck source=../core/contract-utils.sh
  . "${BASH_SOURCE[0]%/*}/../core/contract-utils.sh"
fi
