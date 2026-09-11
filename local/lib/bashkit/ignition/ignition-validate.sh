# Wraps the containerized `ignition-validate` CLI (quay.io/coreos/ignition-validate) so callers
# never need it installed on the host.
# shellcheck shell=bash

readonly __BASHKIT_LIB_IGNITION_VALIDATE_SOURCED="true"
declare -r __IGNITION_VALIDATE_WORKDIR="/data"
declare -r __IGNITION_VALIDATE_FILES_DIR="files"

# usage_ignition_validate()
#
# Prints ignition_validate()'s usage message to stderr.
ignition::usage_ignition_validate() {
  cat <<USAGE >&2
Usage: ignition_validate [-s secret]... [-m workdir_mount_src] [-h] [arg...]

Runs ignition-validate in a container with image quay.io/coreos/ignition-validate:release.

Options:
  -s secret              podman secret spec passed verbatim to \`podman run --secret\`.
                         May be specified multiple times.
  -m workdir_mount_src   Host directory bind-mounted read-only at ${__IGNITION_VALIDATE_WORKDIR}.
  -h                     Print this usage message and exit.

Remaining arguments are passed through to the ignition-validate container.

Environment:
  PODMAN_LOG_LEVEL       podman run log level. (default: warn)
USAGE
}

# ignition_validate()
#
# Runs ignition-validate in a container, passing all non-option arguments through to it.
#
# Globals:
#   PODMAN_LOG_LEVEL   Optional. podman run log level.
# Arguments:
#   -s secret              podman secret spec (repeatable).
#   -m workdir_mount_src   Host directory bind-mounted read-only at the container workdir.
#   -h                     Print usage and return 0.
#   arg...                 Passed through to the ignition-validate container.
# Outputs:
#   Writes ignition-validate's stdout/stderr; usage text to stderr on -h/bad options.
# Returns:
#   ignition-validate's exit status; 1 on option-parsing failure or a duplicate -m.
ignition::validate() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  local -a podman_run_options=()
  local -i OPTIND=1
  local opt workdir_mount_src=""
  while getopts ':s:m:h' opt; do
    case "${opt}" in
      s) podman_run_options+=("--secret=${OPTARG}"); ;;
      m)
        core::is_option_arg_dup "${opt}" "${workdir_mount_src}" \
          || { ignition::usage_ignition_validate; return 1; }
        readonly workdir_mount_src="${OPTARG}"
        ;;
      h) ignition::usage_ignition_validate; return 0; ;;
      :) ignition::usage_ignition_validate; log_error "-${OPTARG} ${__BASHKIT_CORE_LIB_ERROR_OPTION_OPERAND_MISSING}"; return 1; ;;
      ?) ignition::usage_ignition_validate; log_error "-${OPTARG} ${__BASHKIT_CORE_LIB_ERROR_OPTION_UNKNOWN}"; return 1; ;;
    esac
  done
  shift $((OPTIND - 1))

  if [[ -n "${PODMAN_LOG_LEVEL:-}" ]]; then
    podman_run_options+=("--log-level=${PODMAN_LOG_LEVEL}")
  fi

  if [[ -n "${workdir_mount_src}" ]]; then
    local mount_options
    mount_options="type=bind,src=${workdir_mount_src}"
    mount_options+=",target=${__IGNITION_VALIDATE_WORKDIR}"
    mount_options+=",bind-propagation=rslave,no-dereference,ro=true"

    podman_run_options+=(
      "--mount=${mount_options}"
      "--security-opt=label=disable"
    )
  fi

  podman_run_options+=(
    "-i"
    "--rm"
    "--env='IGNITION_*'"
    "--env='IGN_*'"
    "--workdir=${__IGNITION_VALIDATE_WORKDIR}"
  )

  local -r image="quay.io/coreos/ignition-validate:release"
  log_sensitive "$(declare -p image podman_run_options __IGNITION_VALIDATE_WORKDIR)"
  log_sensitive "${FUNCNAME[0]}() options: $*"

  podman run \
    "${podman_run_options[@]}" \
    "${image}" \
    "$@"
}

export -f ignition::validate

if [[ "${__BASHKIT_LIB_CORE_CONTRACT_UTILS_SOURCED:-}" != "true" ]]; then
  # shellcheck source=../core/contract-utils.sh
  . "${BASH_SOURCE[0]%/*}/../core/contract-utils.sh"
fi
