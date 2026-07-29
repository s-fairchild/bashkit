# hack/lib/ignition/installer.sh
#
# shellcheck shell=bash

[ "${XTRACE:-0}" -eq 1 ] && set -x

declare -r __hack_lib_ignition_installer_sourced="true"
declare -r __INSTALLER_WORKDIR="/data"

usage_coreos-installer() {
    cat <<USAGE >&2
Usage: coreos-installer [-s secret]... [-m mount]... [-h] [installer_arg...]

Runs coreos-installer in a container with image quay.io/coreos/coreos-installer:release.

Options:
    -s secret  podman secret spec passed verbatim to \`podman run --secret\`
               (e.g. "mykey,type=mount,target=/data/mykey"). May be specified multiple times.
    -m mount   podman volume mount spec passed verbatim to \`podman run --mount\`.
               May be specified multiple times.
    -h         Print this usage message and exit.

Remaining arguments are passed through to the coreos-installer container.

Environment:
    PODMAN_LOG_LEVEL       podman run log level. (default: warn)
    INSTALLER_VOLUME_MOUNT host directory to mount as the container workdir. (default: \$PWD)
USAGE
}

# coreos-installer()
#
# Runs coreos-installer in a container with image quay.io/coreos/coreos-installer:release.
#
# Options:
#   * -s <spec> - podman secret spec passed verbatim to `podman run --secret`
#                 (e.g. "mykey,type=mount,target=/data/mykey"). Repeatable.
#   * $@        - remaining args are passed to the coreos-installer container.
#
# Environment:
#   * PODMAN_LOG_LEVEL      - string; podman run log level (default: warn).
#   * INSTALLER_VOLUME_MOUNT - string; host directory to mount as the container workdir.
coreos-installer() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    local -a secrets=() mounts=()
    local opt OPTIND=1
    while getopts ':s:m:h' opt; do
        case "$opt" in
            h) usage_coreos-installer; exit 0 ;;
            s)
                secrets+=("$OPTARG")
                ;;
            m)
                mounts+=("$OPTARG")
                ;;
            :)
                usage_coreos-installer
                fatal "-${OPTARG} $ERROR_OPTION_REQUIRED"
                ;;
            ?)
                usage_coreos-installer
                fatal "-${OPTARG} $ERROR_OPTION_UNKNOWN"
                ;;
        esac
    done
    shift $((OPTIND - 1))

    [ -n "${PODMAN_LOG_LEVEL:-}" ] && podman_run_options+=("--log-level=${PODMAN_LOG_LEVEL:-warn}")
    local -r image="quay.io/coreos/coreos-installer:release"
    local -a podman_run_options=(
        "-i"
        "--rm"
        "--env='BU_*'"
        "--security-opt=label=disable"
        "--volume=${PWD}:${__INSTALLER_WORKDIR}"
        "--workdir=${__INSTALLER_WORKDIR}"
    )

    local s
    for s in "${secrets[@]}"; do
        podman_run_options+=("--secret=$s")
    done

    local m
    for m in "${mounts[@]}"; do
        podman_run_options+=("--mount=$m")
    done

    debug "$(declare -p __INSTALLER_WORKDIR)"
    debug "$(declare -p image)"
    debug "$(declare -p podman_run_options)"
    debug "coreos-installer options: $*"

    # shellcheck disable=SC2068
    podman run \
        ${podman_run_options[@]} \
        "$image" \
        $@
}

export -f coreos-installer

declare __bashkit_path="${BASH_SOURCE[0]%/*/*}"
if [ "${____bash_utils_base_config_logging_sourced:-}" != "true" ]; then
    declare __bash_utils_base_config_logging="${__bashkit_path}/../bash-utils/lib/base-config-logging.sh"
    [ -f "$__bash_utils_base_config_logging" ] || { printf '%s\n' "failed to find file: $__bash_utils_base_config_logging" >&2; exit 1; }
    # shellcheck source=../../bash-utils/lib/base-config-logging.sh
    . "$__bash_utils_base_config_logging"
    unset __bash_utils_base_config_logging
fi
unset __bashkit_path
