# shellcheck shell=bash
#
# podman secret helpers: test for a secret, create one from stdin or from
# files, print a secret's data, build a file-driver secretsdata.json, and
# find secrets by label.

readonly __BASHKIT_LIB_PODMAN_SECRET_SOURCED="true"

# TODO move these variables into forge, they are unused in this repo.
readonly __BASHKIT_LIB_PODMAN_SECRETS_METADATA_FILENAME="secrets/secrets.json"
readonly __BASHKIT_LIB_PODMAN_SECRETS_FILEDRIVER_FILENAME="secrets/filedriver/secretsdata.json"

# podman::secret_exists(name)
#
# Tests whether a podman secret with the given name or ID exists. A thin
# wrapper around `podman secret exists` for use in conditionals.
#
# Globals:
#   None.
# Arguments:
#   $1   The podman secret name or ID.
# Outputs:
#   An error and stack trace if <name> is missing or empty.
# Returns:
#   1 if <name> is missing or empty; `podman secret exists`'s exit status
#   otherwise (0 if the secret exists).
podman::secret_exists() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  core::require_operands 1 "$@" || return
  local -r s="${1:-}"

  if [[ -z "${s}" ]]; then
    core::fail "${FUNCNAME[0]}(s=\${1}) s=\$1 cannot be empty." || return
  fi

  podman secret exists "${s}"
}

# podman::usage_secret_create_replace_from_stdin()
#
# Prints podman::secret_create_replace_from_stdin()'s usage message to stderr.
podman::usage_secret_create_replace_from_stdin() {
  cat <<USAGE >&2
Usage: podman::secret_create_replace_from_stdin [-l label]... [-h] secret_name < input

Creates or replaces a podman secret from stdin using \`podman secret create --replace\`.
Fails if stdin is empty. Provenance labels (generating file, sourced file, function
name, and the repo's remote.origin.url when git has one) are always applied.

Options:
  -l label  Additional "key=value" label to apply to the secret.
            May be specified multiple times.
  -h        Print this usage message and return.
USAGE
}

# podman::secret_create_replace_from_stdin([-l label]... secret_name)
#
# Creates or replaces a podman secret from stdin using
# `podman secret create --replace`. Fails if stdin is empty. Always applies
# provenance labels: the generating file, sourced file and function name,
# and the repo's remote.origin.url when `git config` has one.
#
# Globals:
#   None.
# Arguments:
#   -l label   Additional "key=value" label to apply to the secret.
#              Repeatable.
#   -h         Print usage and return 0.
#   $1         The name of the podman secret to create or replace.
# Outputs:
#   Reads the secret data from stdin. Writes `podman secret create`'s output
#   to stdout. Usage text on -h or a bad option; an error and stack trace on
#   a bad option, a missing <secret_name>, empty stdin, or a failed
#   `podman secret create`.
# Returns:
#   0 on success or -h; 1 otherwise.
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
# Prints a podman secret's raw data, using `podman secret inspect
# --showsecret` with the {{.SecretData}} Go template.
#
# Globals:
#   None.
# Arguments:
#   $1   The podman secret name or ID.
# Outputs:
#   The secret's raw data on stdout. An error and stack trace if <name> is
#   missing or empty.
# Returns:
#   1 if <name> is missing or empty; `podman secret inspect`'s exit status
#   otherwise.
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
Usage: podman::secret_create_from_file [-l label]... [-h] src_files_nameref

Creates a podman secret from each file path in the src_files_nameref array. The secret
name is the basename of the source file. Secrets that already exist are skipped with
a warning — delete the secret manually to force recreation. Provenance labels and any
caller-supplied extra labels are applied to each secret.

Options:
  -l label  Additional "key=value" label to apply to each created secret.
            May be specified multiple times.
  -h        Print this usage message and return.

Arguments:
  src_files_nameref  Name of an array variable holding the file paths to create
                     secrets from.
USAGE
}

# podman::secret_create_from_file([-l label]... src_files_nameref)
#
# Creates a podman secret from each file path in the array named by
# <src_files_nameref>, named after the file's basename, with
# `podman secret create --ignore`. Skips, with a warning, any file whose
# secret already exists; delete the secret to recreate it. Applies
# provenance labels (generating file, sourced file, function name and file
# path) and any -l labels to each secret.
#
# Globals:
#   __BASHKIT_CORE_ERROR_OPTION_ARG_REQUIRED
#   __BASHKIT_CORE_ERROR_OPTION_UNKNOWN
# Arguments:
#   -l label   Additional "key=value" label to apply to each secret.
#              Repeatable; each value is passed as --label=<value>.
#   -h         Print usage and return 0.
#   $1         Nameref: the name of an indexed array of file paths.
# Outputs:
#   A warning for each file whose secret already exists, and
#   `podman secret create`'s output. Usage text on -h or a bad option; an
#   error and stack trace on a bad option, a missing operand, or a failed
#   secret creation.
# Returns:
#   0 on success or -h; 1 otherwise.
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
        core::fail "-${OPTARG} ${__BASHKIT_CORE_ERROR_OPTION_ARG_REQUIRED}" \
          || return
        ;;
      ?)
        podman::usage_secret_create_from_file
        core::fail "-${OPTARG} ${__BASHKIT_CORE_ERROR_OPTION_UNKNOWN}" || return
        ;;
    esac
  done
  shift $((OPTIND - 1))
  readonly extra_labels
  log_debug "$(declare -p extra_labels)"

  core::require_operands 1 "$@" || return
  local -n src_files="${1}"
  log_debug "$(declare -p src_files)"

  local secret_name f
  for f in "${src_files[@]}"; do
    log_debug "Iterating over source file: ${f}"

    secret_name="$(basename "${f}")"
    readonly secret_name
    log_debug "$(declare -p secret_name)"

    if podman::secret_exists "${secret_name}"; then
      log_warn "podman secret ${secret_name} already exists. Delete this secret if you intend to update it."
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
    readonly labels
    log_debug "$(declare -p labels)"

    if ! podman secret \
      create \
      --ignore \
      "${labels[@]}" \
      "${secret_name}" \
      "${f}"; then

      log_error "${FUNCNAME[0]}($*) failed to create podman secret from source file: ${f}"
      return 1
    fi
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
# Globals:
#   __BASHKIT_CORE_ERROR_STDIN_NULL
# Arguments:
#   None. Reads podman secret names or IDs from stdin, one per line.
# Outputs:
#   A JSON object on stdout: { "<id>": "<secret_data>", ... }. An error if
#   stdin is a terminal or empty, or if a pipeline stage fails.
# Returns:
#   1 if stdin is a terminal or empty, or if `podman secret inspect` or jq
#   fails; 0 otherwise.
podman::secret_gen_file_secretsdata() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  local input
  input="$(cat)"
  readonly input
  if [[ -t 0 ]]; then
    log_error "${__BASHKIT_CORE_ERROR_STDIN_NULL}"
    return 1
  fi

  [[ -n "${input}" ]] || {
    core::fail "${FUNCNAME[0]}() stdin cannot be empty." || return
  }

  local -a secrets
  mapfile -t secrets <<< "${input}"
  # PIPESTATUS is checked by core::require_pipestatus below.
  # shellcheck disable=SC2312
  podman secret inspect --showsecret "${secrets[@]}" \
    | jq -r 'map({(.ID): .SecretData}) | add'

  core::require_pipestatus "${PIPESTATUS[@]}" || return
}

# podman::secret_filter_by_label(label value names_out)
#
# Collects the names of every podman secret whose Spec.Labels[<label>]
# equals <value> into the caller's array <names_out>. Inspects every
# existing secret and matches with jq, because `podman secret ls --filter`
# can't filter on labels.
#
# Globals:
#   None.
# Arguments:
#   $1   The label key to filter on.
#   $2   The label value to match.
#   $3   Nameref: the name of the caller's array that receives the matching
#        secret names.
# Outputs:
#   An error and stack trace if <names_out> isn't a valid nameref, no
#   secrets exist, the inspect or jq stage fails, or no secret matches.
# Returns:
#   1 on any of the failures above; 0 otherwise.
podman::secret_filter_by_label() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  core::require_operands 3 "$@" || return
  local -r label="${1}"
  local -r value="${2}"
  core::require_nameref "${3}" || return
  local -n names_out="${3}"
  core::is_nameref_valid names_out || return

  local -a secret_ids=()
  readarray -t secret_ids < <(podman secret ls -q) || true
  readonly secret_ids
  log_debug "$(declare -p secret_ids)"

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

if [[ "${__BASHKIT_CORE_CONTRACT_UTILS_SOURCED:-}" != "true" ]]; then
  # shellcheck source=../core/contract-utils.sh
  . "${BASH_SOURCE[0]%/*}/../core/contract-utils.sh"
fi
