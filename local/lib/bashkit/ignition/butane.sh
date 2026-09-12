# Runs the butane CLI in a container: compiles a butane (.bu) config to Ignition JSON.
#
# shellcheck shell=bash

readonly __BASHKIT_LIB_IGNITION_BUTANE_SOURCED="true"
readonly __BASHKIT_LIB_BUTANE_CONTAINER_WORKDIR="/data"

ignition::usage_butane() {
  cat <<USAGE >&2
Usage: butane [-s secret]... [-m dir] [-h] [butane_arg...]

Runs butane in a container with image quay.io/coreos/butane:release.

Options:
  -s secret  podman secret spec passed verbatim to \`podman run --secret\`
             (e.g. "my-key,type=mount,target=/data/files/secrets/my-key").
             May be specified multiple times.
  -m dir     Host directory bind-mounted read-only at the container workdir.
  -h         Print this usage message and exit.

Remaining arguments are passed through to the butane container.

Environment:
  PODMAN_LOG_LEVEL     podman run log level. (default: warn)
  BUTANE_VOLUME_MOUNT  host directory to mount as the container workdir. (default: \$PWD)
USAGE
}

# butane()
#
# Runs butane in a container with image quay.io/coreos/butane:release.
#
# Globals:
#   PODMAN_LOG_LEVEL      podman run log level. (default: warn)
#   BUTANE_VOLUME_MOUNT   host directory to mount as the container workdir.
# Arguments:
#   -s secret  podman secret spec passed verbatim to `podman run --secret`
#              (e.g. "my-key,type=mount,target=/data/files/secrets/my-key"). Repeatable.
#   -m dir     host directory bind-mounted read-only at the container workdir.
#   -h         Print usage and return 0.
#   arg...     Passed through to the butane container.
# Outputs:
#   butane's compiled ignition JSON on stdout; usage/errors on stderr.
# Returns:
#   butane's exit status; 1 on option-parsing failure or a duplicate -m.
ignition::butane() {
  # 1>&2 on every log call in this function: stdout is butane()'s return channel (its callers,
  # e.g. ignition_gen(), pass it straight through as their own compiled-JSON output), so any
  # console-level log write on stdout here would corrupt that output.
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))" 1>&2

  local -a podman_run_options=()
  local opt workdir_mount_src
  local -i OPTIND=1
  while getopts ':s:m:h' opt; do
    case "${opt}" in
      s) podman_run_options+=("--secret=${OPTARG}"); ;;
      m)
        core::is_option_arg_dup "${opt}" "${workdir_mount_src:-}" \
          || { ignition::usage_butane; return 1; }
        readonly workdir_mount_src="${OPTARG}"
        ;;
      h) ignition::usage_butane; return 0; ;;
      :) ignition::usage_butane; log_error "-${OPTARG} ${__BASHKIT_CORE_LIB_ERROR_OPTION_OPERAND_MISSING}"; return 1 ;;
      ?) ignition::usage_butane; log_error "-${OPTARG} ${__BASHKIT_CORE_LIB_ERROR_OPTION_UNKNOWN}"; return 1 ;;
    esac
  done
  shift $((OPTIND - 1))

  if [[ -n "${PODMAN_LOG_LEVEL:-}" ]]; then
    podman_run_options+=("--log-level=${PODMAN_LOG_LEVEL}")
  fi

  if [[ -n "${workdir_mount_src:-}" ]]; then
    if [[ ! -d "${workdir_mount_src}" ]]; then
      log_error "directory not found: ${workdir_mount_src}"
      return 1
    fi

    local mount_options
    mount_options="type=bind,src=${workdir_mount_src}"
    mount_options+=",target=${__BASHKIT_LIB_BUTANE_CONTAINER_WORKDIR}"
    mount_options+=",bind-propagation=rslave,no-dereference,ro=true"

    podman_run_options+=(
      "--mount=${mount_options}"
      "--security-opt=label=disable"
    )
  fi

  podman_run_options+=(
    "-i"
    "--rm"
    "--env='BU_*'"
    "--env='BUTANE_*'"
    "--workdir=${__BASHKIT_LIB_BUTANE_CONTAINER_WORKDIR}"
  )

  local -r image="quay.io/coreos/butane:release"
  log_sensitive "$(declare -p image podman_run_options __BASHKIT_LIB_BUTANE_CONTAINER_WORKDIR)" 1>&2
  log_sensitive "${FUNCNAME[0]}() options: $*" 1>&2

  podman run \
    "${podman_run_options[@]}" \
    "${image}" \
    "$@"
}

if [[ "${__BASHKIT_LIB_CORE_CONTRACT_UTILS_SOURCED:-}" != "true" ]]; then
  # shellcheck source=../core/contract-utils.sh
  . "${BASH_SOURCE[0]%/*}/../core/contract-utils.sh"
fi
