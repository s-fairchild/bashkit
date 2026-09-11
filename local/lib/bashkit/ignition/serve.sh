# Launches a containerized nginx server for serving ignition configs over HTTPS.
#
# shellcheck shell=bash

[[ "${XTRACE:-0}" -eq 1 ]] && set -x

readonly __BASHKIT_LIB_IGNITION_SERVE_SOURCED="true"

# TODO set these as dropin options in forge makefile
# declare -r __NGINX_DROPIN_CONFIGS_SRC="hack/etc/nginx"
# declare -r __NGINX_DROPIN_CONFIG_DEFAULT_SRC="${__NGINX_DROPIN_CONFIGS_SRC}/default.conf"
# declare -r __NGINX_DROPIN_CONFIG_SECURE_SRC="${__NGINX_DROPIN_CONFIGS_SRC}/ignition-secure.conf"

ignition::usage_serve() {
  cat <<USAGE >&2
Usage: serve -c ssl_cert -k ssl_key [-i ignition_secret] [-s secret]... [-d dropin_file]...
             [-e env_prefix]... [-h] [arg...]

Launches a containerised nginx server for serving ignition configs over HTTPS.

Options:
  -i ignition_secret  Name of the podman secret containing the ignition config to serve
                      as config.ign. Omit when ignition is delivered by some other means
                      (e.g. a KubeVirt cloudInitConfigDrive) and only -s secrets need serving.
  -c ssl_cert         Name of the podman secret containing the TLS certificate. (required)
  -k ssl_key          Name of the podman secret containing the TLS private key. (required)
  -s secret           Additional podman secret spec passed verbatim to \`podman run --secret\`
                      (e.g. "mydata,target=/usr/share/nginx/html/secrets/mydata").
                      May be specified multiple times.
  -d dropin_file      Dropin config bind-mounted into /etc/nginx/conf.d/.
                      May be specified multiple times.
                      (default: hack/etc/nginx/default.conf and hack/etc/nginx/ignition-secure.conf)
  -e env_prefix       Host env var wildcard prefix to pass through (e.g. "NGINX_").
                      May be specified multiple times.
  -h                  Print this usage message and exit.

Remaining arguments are passed through to the nginx container.
USAGE
}

# serve()
#
# Launches a containerized nginx server for serving ignition configs over HTTPS.
#
# Globals:
#   PODMAN_LOG_LEVEL   Optional. podman run log level. (default: warn)
# Arguments:
#   -i ignition_secret  Podman secret containing the ignition config to serve as
#         config.ign. Omit when ignition is delivered by some other means (e.g. a
#         KubeVirt cloudInitConfigDrive).
#   -c ssl_cert         Podman secret containing the TLS certificate. (required)
#   -k ssl_key          Podman secret containing the TLS private key. (required)
#   -s secret           Additional podman secret spec passed verbatim to
#         `podman run --secret`. Repeatable.
#   -d dropin_file      Dropin config bind-mounted into /etc/nginx/conf.d/. Repeatable.
#         Defaults to __NGINX_DROPIN_CONFIG_DEFAULT_SRC/__NGINX_DROPIN_CONFIG_SECURE_SRC
#         when omitted.
#   -e env_prefix       Host env var wildcard prefix to pass through (e.g. "NGINX_").
#         Repeatable.
#   -h                  Print usage and return 0.
#   arg...              Trailing args passed through to the nginx container.
# Outputs:
#   Writes podman run's stdout/stderr; usage text to stderr on -h/bad options.
# Returns:
#   podman run's exit status; 1 on option-parsing failure, a duplicate -i/-c/-k, or if
#   podman run fails to start.
ignition::serve() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  local -a secrets=() dropins=() env_prefixes=()
  local opt OPTIND=1 ignition="" ssl_key="" ssl_cert=""
  while getopts ':i:s:d:e:hc:k:' opt; do
    case "${opt}" in
      i)
        core::is_option_arg_dup "${opt}" "${ignition}" \
          || { ignition::usage_serve; return 1; }
        readonly ignition="${OPTARG}"
        ;;
      s) secrets+=("${OPTARG}"); ;;
      d) dropins+=("${OPTARG}"); ;;
      e) env_prefixes+=("${OPTARG}"); ;;
      c)
        core::is_option_arg_dup "${opt}" "${ssl_cert}" \
          || { ignition::usage_serve; return 1; }
        readonly ssl_cert="${OPTARG}"
        ;;
      k)
        core::is_option_arg_dup "${opt}" "${ssl_key}" \
          || { ignition::usage_serve; return 1; }
        readonly ssl_key="${OPTARG}"
        ;;
      h) ignition::usage_serve; return 0; ;;
      :) log_error "-${OPTARG} ${__BASHKIT_CORE_LIB_ERROR_OPTION_OPERAND_MISSING}"; ignition::usage_serve; return 1; ;;
      ?) log_error "-${OPTARG} ${__BASHKIT_CORE_LIB_ERROR_OPTION_UNKNOWN}"; ignition::usage_serve; return 1; ;;
    esac
  done
  shift $((OPTIND - 1))

  if [[ -z "${ssl_cert}" ]]; then
    ignition::usage_serve
    log_error "-c ${__BASHKIT_CORE_LIB_ERROR_OPTION_OPERAND_MISSING}"
    return 1
  fi

  if [[ -z "${ssl_key}" ]]; then
    ignition::usage_serve
    log_error "-k ${__BASHKIT_CORE_LIB_ERROR_OPTION_OPERAND_MISSING}"
    return 1
  fi

  if (( ! ${#secrets[@]} )); then
    log_warn "No -s option(s) provided. No secrets will be mounted."
  fi

  log_sensitive "$(declare -p ignition secrets dropins env_prefixes ssl_cert ssl_key)"

  local -r ssl_root="/run/secrets"
  local -r __ssl_cert_mount_path="${ssl_root}/ssl-cert"
  local -r __ssl_key_mount_path="${ssl_root}/ssl-key"
  local -a podman_run_options=(
    "--rm"
    "-i"
    "--pull=missing"
    "--security-opt=label=disable"
    "--log-level=${PODMAN_LOG_LEVEL:-warn}"
    "--publish=0.0.0.0:8180:8080"
    "--publish=0.0.0.0:8181:8081"
    "--secret=${ssl_cert},target=${__ssl_cert_mount_path},mode=0400,uid=65532,gid=65532"
    "--secret=${ssl_key},target=${__ssl_key_mount_path},mode=0400,uid=65532,gid=65532"
  )

  local -r nginx_serve_root="/usr/share/nginx/html"
  if [[ -n "${ignition:-}" ]]; then
    # Set ignition file to be served as index root
    local secret_options="${ignition}"
    secret_options+=",target=${nginx_serve_root}/config.ign"
    secret_options+=",mode=0444"
    podman_run_options+=("--secret=${secret_options}")
  fi

  local -r nginx_dropin_target="/etc/nginx/conf.d"
  local item
  for item in "${dropins[@]}"; do
    if [[ -f "${item}" ]]; then
      podman_run_options+=("--volume=./${item}:${nginx_dropin_target}/$(basename "${item}"):ro")
    else
      ignition::usage_serve
      log_error "dropin file not found: ${item}"
      return 1
    fi
  done

  for item in "${secrets[@]}"; do
    if podman secret exists "${item}"; then
      podman_run_options+=("--secret=${item},target=${nginx_serve_root}/secrets/${item}")
    else
      ignition::usage_serve
      log_error "podman secret not found: ${item}"
      return 1
    fi
  done

  for item in "${env_prefixes[@]}"; do
    # Strip a trailing '*' so an already-globbed prefix does not become '**'.
    podman_run_options+=("--env=${item%\*}*")
  done
  log_sensitive "$(declare -p podman_run_options)"

  # https://images.redhat.com/?name=nginx&version=latest
  local -r image="registry.access.redhat.com/hi/nginx:latest"

  if ! podman run \
    "${podman_run_options[@]}" \
    "${image}" \
    "$@"; then
    log_error "podman run command failed."
    return 1
  fi
}

if [[ "${__BASHKIT_LIB_CORE_CONTRACT_UTILS_SOURCED:-}" != "true" ]]; then
  # shellcheck source=../core/contract-utils.sh
  . "${BASH_SOURCE[0]%/*}/../core/contract-utils.sh"
fi
