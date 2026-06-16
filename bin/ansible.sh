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
    ansible_arg="${FUNCNAME[0]}"
    local -r regex="$(IFS='|'; echo "${__ANSIBLE_ARGS[*]}")"
    if [[ "${1:-}" =~ $regex ]]; then
        ansible_arg+="-$1"
        shift
    fi

    local -ar podman_run_options=(
        "-it"
        "--rm"
        "--pull=missing"
        "--mount=type=bind,src=${PWD},target=${__ANSIBLE_WORKDIR},bind-propagation=rslave,no-dereference,ro=true"
        "--workdir=/apps"
        "--env='ANSIBLE_*'"
    )

    if [ ! -v ANSIBLE_CONFIG ] && [ -f "$__ANSIBLE_CONFIG" ]; then
        podman_run_options+=("--env='ANSIBLE_CONFIG=${ANSIBLE_CONFIG:-$__ANSIBLE_CONFIG}")
    fi
    [ -d "${HOME}.ssh" ] && podman_run_options+=("--mount=type=bind,src=${HOME}/.ssh,target=/root/.ssh,bind-propagation=slave,ro=true")
    [ -d "$__ANSIBLE_COLLECTIONS_DIR" ] && podman_run_options+=("--mount=type=bind,src=${__ANSIBLE_COLLECTIONS_DIR},target=/usr/share/ansible/collections,bind-propagation=rslave,no-dereference,ro=true")

    debug "$(declare -p podman_run_options)"
    debug "$(declare -p __ANSIBLE_PODMAN_IMAGE)"

    # shellcheck disable=SC2068
    podman run \
        ${podman_run_options[@]} \
        "${__ANSIBLE_PODMAN_IMAGE}" \
        "${ansible_arg}" \
        "$@"
}

ansible-playbook() {
    ansible playbook "$@"
}

ansible-inventory() {
    ansible inventory "$@"
}

ansible-galaxy() {
    ansible galaxy "$@"
}

ansible-config() {
    ansible config "$@"
}

if [ "${__lib_opt_bash_utils_logging_sourced:-}" != "true" ]; then
    declare -r lib_opt_bash_utils_logging="hack/lib/opt-bash-utils-logging.sh"
    [ -f "$lib_opt_bash_utils_logging" ] || { printf '%s\n' "failed to find file: $lib_opt_bash_utils_logging" >&2; exit 1; }
    # shellcheck source=../lib/opt-bash-utils-logging.sh
    . "$lib_opt_bash_utils_logging"
fi
