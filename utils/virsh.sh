# shellcheck shell=bash

declare -r __opt_name="n"
declare -r __opt_arch="a"
declare -r __opt_vcpus="c"
declare -r __opt_disk_gb="d"
declare -r __opt_graphics="g"
declare -r __opt_image="i"
declare -r __opt_ram_mb="r"
declare -r __opt_stream="s"
declare -r __opt_os_variant="v"
declare -r __opt_network="b"
declare -r __opt_ignition="f"
declare -r __opt_help="h"

virsh_install_fcos() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    local opt OPTIND=1
    local name arch graphics image stream os_variant network ignition
    local -i vcpus disk_gb ram_mb
    local -a disks=()

    local -r getopts_str=":${__opt_name}:${__opt_arch}:${__opt_vcpus}:${__opt_disk_gb}:${__opt_graphics}:${__opt_image}:${__opt_ram_mb}:${__opt_stream}:${__opt_os_variant}:${__opt_network}:${__opt_ignition}:${__opt_help}"

    while getopts "${getopts_str}" opt; do
        case "$opt" in
            "$__opt_name")
                is_option_duplicate "$name" "$__opt_name"
                name="$OPTARG"
                ;;
            "$__opt_arch")
                is_option_duplicate "$arch" "$__opt_arch"
                arch="$OPTARG"
                ;;
            "$__opt_vcpus")
                is_option_duplicate "$vcpus" "$__opt_vcpus"
                vcpus="$OPTARG"
                ;;
            "$__opt_disk_gb")
                is_option_duplicate "$disk_gb" "$__opt_disk_gb"
                disk_gb="$OPTARG"
                ;;
            "$__opt_graphics")
                is_option_duplicate "$graphics" "$__opt_graphics"
                graphics="$OPTARG"
                ;;
            "$__opt_image")
                is_option_duplicate "$image" "$__opt_image"
                image="$OPTARG"
                ;;
            "$__opt_ram_mb")
                is_option_duplicate "$ram_mb" "$__opt_ram_mb"
                ram_mb="$OPTARG"
                ;;
            "$__opt_stream")
                is_option_duplicate "$stream" "$__opt_stream"
                stream="$OPTARG"
                ;;
            "$__opt_os_variant")
                is_option_duplicate "$os_variant" "$__opt_os_variant"
                os_variant="$OPTARG"
                ;;
            "$__opt_network")
                is_option_duplicate "$network" "$__opt_network"
                network="$OPTARG"
                ;;
            "$__opt_ignition")
                is_option_duplicate "$ignition" "$__opt_ignition"
                # Not setting as readonly so that it can be unset as soon as we're finished with it.
                # In case there is sensitive data within the ignition string.
                ignition="$OPTARG"
                ;;
            "$__opt_help")
                info "TODO create usage statement function."
                return 0
                ;;
            :)
                fatal "-${OPTARG} ${ERROR_OPTION_REQUIRED}"
                ;;
            ?)
                fatal "-${OPTARG} ${ERROR_OPTION_UNKNOWN}"
                ;;
        esac
    done
    shift $((OPTIND - 1))

    # qcow2 expected
    local -r image="${image?$(fatal "${ERROR_OPTION_REQUIRED}: -${__opt_image}")}"
    local -r name="${name:="fcos-$RANDOM"}"
    local -r vcpus="${vcpus:=2}"
    local -r ram_mb="${ram_mb:=2048}"
    local -r stream="${stream:='stable'}"
    local -r disk_gb="${disk_gb:=10}"

    [ -v ignition ] && fatal "$ERROR_OPTION_REQUIRED: -${__opt_ignition}"

    # xtrace must be off *before* the -f test below: we don't yet know whether
    # $ignition is a path or a secret string, and it's the traced command line
    # that would leak it, not the test's result.
    # shellcheck disable=SC2034 # populated via nameref inside with_xtrace_suppressed
    local -i ignition_xtrace_was_on=0
    with_xtrace_suppressed save ignition_xtrace_was_on

    local ignition_type="string"
    if [ -f "$ignition" ]; then
        ignition_type="file"
        # Just a path from here on -- safe to resume tracing early.
        with_xtrace_suppressed restore ignition_xtrace_was_on
    fi

    # For x86 / aarch64
    local -a ignition_device_arg=(--qemu-commandline="-fw_cfg name=opt/com.coreos/config,${ignition_type}=${ignition}")
    unset ignition

    # TODO allow setting ignition config as a local file in addition to a string
    # Setup the correct SELinux label to allow access to the config
    # chcon --verbose --type svirt_home_t ${IGNITION_CONFIG}

    # ignition_device_arg still carries the raw string here, and it's about to
    # be expanded onto the virt-install command line below -- restoring xtrace
    # before that call would trace the secret right back out again, so the
    # string branch stays suppressed through the call itself and only
    # restores after (see the final with_xtrace_suppressed call below).
    virt-install --connect="qemu:///system" \
                 --name="${VM_NAME}" \
                 --vcpus="${VCPUS}" \
                 --memory="${RAM_MB}" \
                 --os-variant="fedora-coreos-$STREAM" \
                 --import \
                 --graphics=none \
                 --disk="size=${DISK_GB},backing_store=${IMAGE}" \
                 --network bridge=virbr0 \
                 "${ignition_device_arg[@]}"

    # if/fi (not `&&`): this is the last statement in the function, and under
    # this repo's errexit + ERR trap, a bare `[ cond ] && cmd` here would make
    # the function's own return status 1 (cond's failing status) whenever
    # ignition_type is "file", aborting whatever called virsh_install_fcos.
    if [ "$ignition_type" = "string" ]; then
        with_xtrace_suppressed restore ignition_xtrace_was_on
    fi
}

virsh() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    command virsh
}

export -f virsh virsh_install_fcos

declare __bashkit_path="${BASH_SOURCE[0]%/*/*}"
if [ "${__bashkit_lib_getopts_options_sourced:-}" != "true" ]; then
    declare __bashkit_lib_getopts_options="${__bashkit_path}lib/getopts/options.sh"
    [ -f "$__bashkit_lib_getopts_options" ] || { printf '%s\n' "failed to find file: ${__bashkit_lib_getopts_options}" >&2; exit 1; }
    # shellcheck source=../../bash-utils/lib/base-config-logging.sh
    . "$__bashkit_lib_getopts_options"
    unset __bashkit_lib_getopts_options
fi
if [ "${__bashkit_suppressed_sourced:-}" != "true" ]; then
    declare __bashkit_suppressed="${__bashkit_path}/suppressed.sh"
    [ -f "$__bashkit_suppressed" ] || { printf '%s\n' "failed to find file: ${__bashkit_suppressed}" >&2; exit 1; }
    # shellcheck source=../suppressed.sh
    . "$__bashkit_suppressed"
    unset __bashkit_suppressed
fi
unset __bashkit_path
