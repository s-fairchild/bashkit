# hack/lib/podman/podman-secret.sh
#
# shellcheck shell=bash

[[ "${XTRACE:-0}" -eq 1 ]] && set -x

readonly __BASHKIT_LIB_PODMAN_SECRET_SOURCED="true"

# TODO move these variables into forge, they are unused in this repo.
readonly __BASHKIT_LIB_PODMAN_SECRETS_METADATA_FILENAME="secrets/secrets.json"
readonly __BASHKIT_LIB_PODMAN_SECRETS_FILEDRIVER_FILENAME="secrets/filedriver/secretsdata.json"

# podman::secret_exists(name)
#
# Returns 0 if a podman secret with the given name or ID exists, non-zero otherwise.
# Thin wrapper around `podman secret exists` for use in conditional expressions.
#
# Arguments:
#   $1   Podman secret name or ID to check.
# Returns:
#   0 if the secret exists; `podman secret exists`'s exit status otherwise.
podman::secret_exists() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  core::require_operands 1 "$@" || return
  local -r s="${1:-}"

  [[ -n "${s}" ]] || {
    core::fail "${FUNCNAME[0]}(s=\${1}) s=\$1 cannot be empty." || return
  }

  podman secret exists "${s}"
}

# podman::usage_secret_create_replace_from_stdin()
#
# Prints podman::secret_create_replace_from_stdin()'s usage message to stderr.
podman::usage_secret_create_replace_from_stdin() {
  cat <<USAGE >&2
Usage: podman_secret_create_replace_from_stdin [-l label]... [-h] secret_name < input

Creates or replaces a podman secret from stdin using \`podman secret create --replace\`.
Reads secret data from stdin; aborts if stdin is empty. Standard provenance labels
(generating file, sourced file, function name) are always applied.

Options:
  -l label  Additional "key=value" label to apply to the secret.
            May be specified multiple times.
  -h        Print this usage message and exit.
USAGE
}

# podman::secret_create_replace_from_stdin([-l label]... secret_name)
#
# Creates or replaces a podman secret from stdin using `podman secret create --replace`.
# Reads secret data from stdin; aborts if stdin is empty.
# Standard provenance labels (generating file, sourced file, function name) are always
# applied.
#
# Arguments:
#   -l label       Additional "key=value" label to apply to the secret. Repeatable.
#   secret_name    Name of the podman secret to create or replace.
# Outputs:
#   Reads secret data from stdin.
# Returns:
#   Non-zero (via fatal) if the secret name/stdin are missing, or secret creation fails.
podman::secret_create_replace_from_stdin() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  local -a extra_labels=()
  local opt OPTIND=1
  while getopts ':l:h' opt; do
    case "${opt}" in
      h) podman::usage_secret_create_replace_from_stdin; return 0; ;;
      l) extra_labels+=("${OPTARG}"); ;;
      :)
        podman::usage_secret_create_replace_from_stdin
        core::fail "-${OPTARG} requires an operand." || return
        ;;
      ?)
        podman::usage_secret_create_replace_from_stdin
        core::fail "-${OPTARG} unknown option." || return
        ;;
    esac
  done
  shift $((OPTIND - 1))
  readonly extra_labels

  core::require_operands 1 "$@" || return
  local -r secret_name="${1:-}"

  local input
  input="$(cat)"
  readonly input
  [[ -n "${input}" ]] || {
    core::fail "${FUNCNAME[0]}() stdin cannot be empty." || return
  }

  local -a labels=()
  local remote_origin_url
  if remote_origin_url="$(git config get remote.origin.url)"; then
    readonly remote_origin_url
    labels+=("--label=remote.origin.url=${remote_origin_url}")
  fi

  labels+=(
    "--label=generated-by-file=$(basename "$0")"
    "--label=generated-by-sourced-file=${BASH_SOURCE[0]}"
    "--label=generated-by-function=${FUNCNAME[0]}()"
  )

  local l
  for l in "${extra_labels[@]}"; do
    labels+=("--label=${l}")
  done
  readonly labels
  log_debug "$(declare -p labels)"

  printf '%s' "${input}" \
    | podman secret \
        create \
        --replace \
        "${labels[@]}" \
        "${secret_name}" \
        - \
    || {
      local msg="${FUNCNAME[0]}() failed to create podman secret"
      msg+=": ${secret_name}"
      readonly msg
      core::fail "${msg}" || return
    }
}

# podman::secret_showsecret(name)
#
# Prints the raw secret data for a named podman secret to stdout.
# Uses `podman secret inspect --showsecret` with the SecretData Go template field.
# Aborts if the secret name argument is missing or empty.
#
# Arguments:
#   $1   Podman secret name to retrieve data from.
# Outputs:
#   Writes the secret's raw data to stdout.
# Returns:
#   Non-zero (via fatal) if the secret name is missing or empty.
podman::secret_showsecret() {
  log_debug "Starting ${FUNCNAME[0]}()"
  core::require_operands 1 "$@" || return
  local -r s="${1:-}"

  [[ -n "${s}" ]] || {
    log_error "${FUNCNAME[0]}(s="") s=\${1} cannot be empty string."
    core::fail || return
  }

  podman secret \
    inspect \
    --showsecret \
    -f '{{.SecretData}}' \
    "${s}"
}

# podman::usage_secret_create_from_file()
#
# Prints podman::secret_create_from_file()'s usage message to stderr.
podman::usage_secret_create_from_file() {
  cat <<USAGE >&2
Usage: podman_secret_create_from_file [-l label]... [-h] src_files_nameref

Creates a podman secret for each file path or glob in the src_files array. The secret
name is the basename of the source file. Secrets that already exist are skipped with
a warning — delete the secret manually to force recreation. Provenance labels and any
caller-supplied extra labels are applied to each secret.

Options:
  -l label  Additional "key=value" label to apply to each created secret.
            May be specified multiple times.
  -h        Print this usage message and exit.

Arguments:
  src_files_nameref  Name of an array variable holding file paths or glob patterns
                     to create secrets from.
USAGE
}

# podman::secret_create_from_file([-l label]... src_files_nameref)
#
# Creates a podman secret for each file path or glob in the src_files array.
# The secret name is the basename of the source file. Secrets that already exist
# are skipped with a warning — delete the secret manually to force recreation.
# Provenance labels and any caller-supplied extra labels are applied to each secret.
#
# Arguments:
#   -l label       Additional "key=value" label to apply to each created secret.
#                  Repeatable; each value is passed as --label=<value>.
#   src_files      Nameref name; array of file paths or glob patterns to create
#                  secrets from. Each element is expanded and its basename becomes
#                  the secret name.
# Outputs:
#   Warns to stderr for each source file whose secret already exists.
# Returns:
#   Non-zero on bad options, a missing operand, or a failed secret creation.
podman::secret_create_from_file() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  local -a extra_labels=()
  local opt OPTIND=1
  while getopts ':l:h' opt; do
    case "${opt}" in
      l)
        extra_labels+=("${OPTARG}")
        ;;
      h)
        podman::usage_secret_create_from_file
        return 0
        ;;
      :)
        podman::usage_secret_create_from_file
        core::fail "-${OPTARG} ${ERROR_OPTION_ARG_REQUIRED}" || return
        ;;
      ?)
        podman::usage_secret_create_from_file
        core::fail "-${OPTARG} ${ERROR_OPTION_UNKNOWN}" || return
        ;;
    esac
  done
  shift $((OPTIND - 1))

  core::require_operands 1 "$@" || return
  local -n src_files="$1"

  local secret_name f
  for f in "${src_files[@]}"; do
    secret_name="$(basename "${f}")"

    if podman_secret_exists "${secret_name}"; then
      log_warn "podman secret ${secret_name} already exists." \
        "Delete this secret if you intend to update it."
      continue
    fi

    local -a labels=(
      "--label=generated-by-file=$(basename "$0")"
      "--label=generated-by-sourced-file=${BASH_SOURCE[0]}"
      "--label=generated-by-function=${FUNCNAME[0]}()"
      "--label=filepath=${f}"
    )

    local l
    for l in "${extra_labels[@]}"; do
      labels+=("--label=${l}")
    done
    log_debug "$(declare -p labels)"

    podman secret \
      create \
      --ignore \
      "${labels[@]}" \
      "${secret_name}" \
      "${f}" \
      || {
        local msg="${FUNCNAME[0]}() failed to create podman secret"
        msg+=": ${f}"
        core::fail "${msg}" || return
      }
  done
}

# podman::secret_gen_file_secretsdata()
#
# Generates a secretsdata.json blob in the format expected by the podman file
# secret driver. Reads a whitespace-separated list of secret names or IDs from
# stdin, inspects each with `podman secret inspect --showsecret`, and produces a
# JSON object mapping each secret ID to its raw secret data.
#
# The output can be written to /var/lib/containers/storage/secrets/filedriver/secretsdata.json
# on a target host to pre-populate the podman secret store without running
# `podman secret create` on that host (e.g. via ignition file injection).
#
# Arguments:
#   (stdin)   Whitespace-separated list of podman secret names or IDs to include.
# Outputs:
#   Writes a JSON object to stdout: { "<id>": "<secret_data>", ... }
# Returns:
#   1 if stdin is a TTY (i.e. nothing was piped in).
podman::secret_gen_file_secretsdata() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  local input
  input="$(cat)"
  readonly input
  if [[ -t 0 ]]; then
    log_error "${ERROR_STDIN_NULL}"
    return 1
  fi

  [[ -n "${input}" ]] || {
    core::fail "${FUNCNAME[0]}() stdin cannot be empty." || return
  }

  local -a secrets
  mapfile secrets <<< "${input}"
  # PIPESTATUS is checked by core::require_pipestatus below.
  # shellcheck disable=SC2312
  podman secret inspect --showsecret "${secrets[@]}" \
    | jq -r 'map({(.ID): .SecretData}) | add'

  core::require_pipestatus "${PIPESTATUS[@]}" || return
}

# podman::secret_filter_by_label(label value)
#
# Prints the names of all podman secrets carrying the given label key/value pair.
# Inspects every existing secret and selects those whose Spec.Labels[label] equals
# value. (`podman secret ls --filter` does not support label filtering, so the
# match is performed with jq.)
#
# Arguments:
#   $1   Label key to filter on.
#   $2   Expected label value.
# Outputs:
#   Writes matching podman secret names to stdout, newline-separated.
# Returns:
#   1 if the jq filter fails to parse, or no secret matches.
podman::secret_filter_by_label() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  core::require_operands 3 "$@" || return
  local -r label="${1}"
  local -r value="${2}"
  local -n names_out="${3}"

  core::require_nameref "${names_out}" || return
  core::is_nameref_valid "${names_out}" || return

  local -a secret_ids=()
  readarray -t secret_ids < <(podman secret ls -q) || true
  readonly secret_ids
  log_debug "$(declare -p secrets)"

  (( "${#secret_ids[@]}" )) || {
    core::fail "No podman secret IDs could be found." || return
  }

  # These are json variables not intended to be expanded by bash.
  # shellcheck disable=SC2016
  local -r jmes_query='.[] | select(.Spec.Labels[$label] == $value) | .Spec.Name'

  # We want multiple names to be split into multiple elements here.
  # shellcheck disable=SC2207
  # PIPESTATUS is checked by core::require_pipestatus below.
  # shellcheck disable=SC2312
  names_out=($(
    podman secret inspect "${secret_ids[@]}" \
      | jq -r \
          --arg label "${label}" \
          --arg value "${value}" \
          "${jmes_query}"
  )) || {
    local msg="failed to parse podman secret data with filter:"
    msg+=".Spec.Labels[\"${label}\"] == \"${value}\""
    core::fail "${msg}" || return
  }
  core::require_pipestatus "${PIPESTATUS[@]}" || return

  if [[ -z "${names_out[*]}" ]]; then
    local msg="no podman secret found with filter:"
    msg+=".Spec.Labels[\"${label}\"] == \"${value}\""
    core::fail "${msg}" || return
  fi
}

if [[ "${__BASHKIT_LIB_CORE_CONTRACT_UTILS_SOURCED:-}" != "true" ]]; then
  # shellcheck source=../core/contract-utils.sh
  . "${BASH_SOURCE[0]%/*}/../core/contract-utils.sh"
fi
