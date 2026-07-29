# shellcheck shell=bash

declare -r __vendor_bashkit_lib_virsh_virt_install_fcos_sourced="true"
declare -r __opt_name="n"
declare -r __opt_connect="p"
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
    log_sensitive "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    local vm_name connect arch graphics image stream os_variant network ignition
    local -i vcpus disk_gb ram_mb
    local -r getopts_str=":${__opt_name}:${__opt_connect}:${__opt_arch}:${__opt_vcpus}:${__opt_disk_gb}:${__opt_graphics}:${__opt_image}:${__opt_ram_mb}:${__opt_stream}:${__opt_os_variant}:${__opt_network}:${__opt_ignition}:${__opt_help}"
    local opt OPTIND=1
    while getopts "${getopts_str}" opt; do
        case "$opt" in
            "$__opt_name")
                is_option_duplicate "$vm_name" "$__opt_name"
                vm_name="$OPTARG"
                ;;
            "$__opt_connect")
                is_option_duplicate "$connect" "$__opt_connect"
                connect="$OPTARG"
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
                log_info "TODO create usage statement function."
                return 0
                ;;
            :)
                log_fatal "-${OPTARG} ${ERROR_OPTION_REQUIRED}"
                ;;
            ?)
                log_fatal "-${OPTARG} ${ERROR_OPTION_UNKNOWN}"
                ;;
        esac
    done
    shift $((OPTIND - 1))

    [ -n "${image:-}" ] || log_fatal "${ERROR_OPTION_REQUIRED}: -${__opt_image}"
    [ -v ignition ] && log_fatal "$ERROR_OPTION_REQUIRED: -${__opt_ignition}"

    local -a virt_install_options=(
        "--connect=${connect:-'qemu:///system'}"
        "--name=${vm_name:-"fcos-$RANDOM"}"
        "--vcpus=${vcpus:-2}"
        "--memory=${ram_mb:-2048}"
        "--os-variant=fedora-coreos-${stream:-'stable'}"
        "--import"
        "--graphics=none"
        "--disk=size=${disk_gb:-10},backing_store=${image}"
        "--network network=${network},portForward0=127.0.0.1:6443:6443,portForward1=127.0.0.1:80:8080"
    )

    log_debug "$(declare -p virt_install_options)"

    # xtrace must be off *before* the -f test below: we don't yet know whether
    # $ignition is a path or a secret string, and it's the traced command line
    # that would leak it, not the test's result.
    # shellcheck disable=SC2034 # populated via nameref inside with_xtrace_suppressed
    local -i ignition_xtrace_was_on=0
    with_xtrace_suppressed save ignition_xtrace_was_on

    local ignition_type="string"
    if [ -f "$ignition" ]; then
        ignition_type="file"

        chcon --verbose \
              --type svirt_home_t \
              "$ignition"

        # Safe to resume tracing early.
        with_xtrace_suppressed restore ignition_xtrace_was_on
    fi
    log_debug "$(declare -p ignition_type)"

    # For x86 / aarch64
    virt_install_options+=(--qemu-commandline="-fw_cfg name=opt/com.coreos/config,${ignition_type}=${ignition}")
    unset ignition

    # ignition_device_arg still carries the raw string here, and it's about to
    # be expanded onto the virt-install command line below -- restoring xtrace
    # before that call would trace the secret right back out again, so the
    # string branch stays suppressed through the call itself and only
    # restores after (see the final with_xtrace_suppressed call below).
    #
    # shellcheck disable=SC2068
    virt-install ${virt_install_options[@]} $@

    # if/fi (not `&&`): this is the last statement in the function, and under
    # this repo's errexit + ERR trap, a bare `[ cond ] && cmd` here would make
    # the function's own return status 1 (cond's failing status) whenever
    # ignition_type is "file", aborting whatever called virsh_install_fcos.
    if [ "$ignition_type" = "string" ]; then
        with_xtrace_suppressed restore ignition_xtrace_was_on
    fi
}

# logging library is sourced in options.sh (and suppressed.sh), there is no need to source it here.
if [ "${__vendor_bashkit_utils_options_sourced:-}" != "true" ]; then
    declare __vendor_bashkit_utils_options="hack/vendor/bashkit/utils/getopts/options.sh"
    [ -f "$__vendor_bashkit_utils_options" ] || { printf '%s\n' "failed to find file: ${__vendor_bashkit_utils_options}" >&2; exit 1; }
    # shellcheck source=../../utils/options.sh
    . "$__vendor_bashkit_utils_options"
    unset __vendor_bashkit_utils_options
fi
if [ "${__vendor_bashkit_utils_suppressed_sourced:-}" != "true" ]; then
    declare __vendor_bashkit_utils_suppressed="hack/vendor/bashkit/utils/suppressed.sh"
    [ -f "$__vendor_bashkit_utils_suppressed" ] || { printf '%s\n' "failed to find file: ${__vendor_bashkit_utils_suppressed}" >&2; exit 1; }
    # shellcheck source=../../utils/suppressed.sh
    . "$__vendor_bashkit_utils_suppressed"
    unset __vendor_bashkit_utils_suppressed
fi
