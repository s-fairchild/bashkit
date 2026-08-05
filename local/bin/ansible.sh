# hack/bin/ansible.sh
#
# shellcheck shell=bash

# declare -r __ANSIBLE_PODMAN_IMAGE="docker.io/alpine/ansible"
declare -r __ANSIBLE_PODMAN_IMAGE="docker.io/alpine/ansible"

# declare -r __ANSIBLE_WORKDIR="/apps"
declare -r __ANSIBLE_WORKDIR="/apps"

# declare -r __ANSIBLE_COLLECTIONS_DIR="/deploy/ansible/collections"
declare -r __ANSIBLE_COLLECTIONS_DIR="/deploy/ansible/collections"

# declare -r __ANSIBLE_CONFIG="/apps/deploy/ansible/ansible.cfg"
declare -r __ANSIBLE_CONFIG="/apps/deploy/ansible/ansible.cfg"

# declare -r __ANSIBLE_ARGS=(
#    "playbook"
#    "inventory"
#    "galaxy"
#    "config"
# )
declare -r __ANSIBLE_ARGS=(
    "playbook"
    "inventory"
    "galaxy"
    "config"
)

ansible() {
    log_sensitive "Starting ${BASH_LINENO[$*]} ${FUNCNAME[0]}($*)"

    local -i OPTIND
    local opt subcmd
    local -a mounts=()
    while getopts ":m:s:" opt; do
        case "${opt}" in
            m)
                # Example option to provide
                # "-m type=bind,src=${PWD},target=${__ANSIBLE_WORKDIR},bind-propagation=rslave,no-dereference,ro=true"
                log_debug "$(declare -p OPTARG)"
                m="--mount=${OPTARG}"
                log_info "Appending to podman run option: ${m}"
                mounts+=("$m")
                ;;
            s)
                log_debug "$(declare -p OPTARG)"
                [ -z "${subcmd}" ] || log_fatal "-s <subcommand> only one subcmd can be specified."

                local -r regex="$(IFS='|'; echo "${__ANSIBLE_ARGS[*]}")"
                [[ "${subcmd}" =~ $regex ]] || log_fatal "-s <subcmd> must be one of: ${__ANSIBLE_ARGS[*]}"

                subcmd="${OPTARG}"
                local -r subcmd
                ;;
            :)
                log_fatal "Option -${OPTARG} requires an argument"
                ;;
            \?)
                log_fatal "Invalid option: -${OPTARG}"
                ;;
        esac
    done
    shift $((OPTIND - 1))

    local -ar podman_run_options=(
        "--name"
        "${FUNCNAME[0]}-${subcmd}-$$"
        "-i"
        "--rm"
        "--pull=missing"
        "--workdir=/apps"
        "--env='ANSIBLE_*'"
    )

    if [ -d "${HOME}.ssh" ]; then
        podman_run_options+=("--mount=type=bind,src=${HOME}/.ssh,target=/root/.ssh,bind-propagation=slave,ro=true")
    fi
    # TODO make this simpler, such as mounting a named podman volume.
    # if [ -d "$__ANSIBLE_COLLECTIONS_DIR" ]; then
        # podman_run_options+=("--mount=type=bind,src=${__ANSIBLE_COLLECTIONS_DIR},target=/usr/share/ansible/collections,bind-propagation=rslave,no-dereference,ro=true")
    # fi

    log_debug "$(declare -p podman_run_options)"
    log_debug "$(declare -p __ANSIBLE_PODMAN_IMAGE)"

    # shellcheck disable=SC2068
    podman run \
           ${podman_run_options[@]} \
           "${__ANSIBLE_PODMAN_IMAGE}" \
           "$subcmd" \
           ${@}
}

ansible-playbook() {
    log_sensitive "Starting ${BASH_LINENO[$*]} ${FUNCNAME[0]}($*)"
    ansible \
           -s playbook \
           "$@"
}

ansible-inventory() {
    log_sensitive "Starting ${BASH_LINENO[$*]} ${FUNCNAME[0]}($*)"
    ansible \
           -s inventory \
           "$@"
}

ansible-galaxy() {
    log_sensitive "Starting ${BASH_LINENO[$*]} ${FUNCNAME[0]}($*)"
    ansible \
           -s galaxy \
           "$@"
}

ansible-config() {
    log_sensitive "Starting ${BASH_LINENO[$*]} ${FUNCNAME[0]}($*)"
    ansible \
           -s config \
           "$@"
}

if [ "${__lib_opt_bash_utils_logging_sourced:-}" != "true" ]; then
    declare lib_bash_logger_logging_sh="lib/bash-logger/logging.sh"
    declare local_lib_bash_logger_logging="${HOME}/.local/${lib_bash_logger_logging_sh}"
    declare home_src_github_com_s_fairchild_bash_logger_logging="${HOME}/src/github.com/s-fairchild/bash-logger/logging.sh"
    declare usr_local_lib_bash_logger_logging="/usr/local/${lib_bash_logger_logging_sh}"

    if [ -f "$local_lib_bash_logger_logging" ]; then
        # shellcheck source=../../../../../../.local/lib/bash-logger/logging.sh disable=SC1091
        . "$local_lib_bash_logger_logging"
    elif [ -f "$home_src_github_com_s_fairchild_bash_logger_logging" ]; then
        # shellcheck source=../../../bash-logger/logging.sh
        . "$home_src_github_com_s_fairchild_bash_logger_logging"
    elif [ -f "$usr_local_lib_bash_logger_logging" ]; then
        # shellcheck source=/usr/local/lib/bash-logger/logging.sh disable=SC1091
        . "$usr_local_lib_bash_logger_logging"
    fi
fi

# TODO create a shared library function based on https://github.com/s-fairchild/bash-logger/blob/4f3ff26ac1c524a0eaeac325d212578258d7ba7e/docs/examples.md#L133
