# hack/lib/podman/build/build_multi_stage.sh
#
# shellcheck shell=bash

readonly __BASHKIT_LIB_PODMAN_BUILD_SOURCED="true"
readonly ARGFILE_CONF="argfile.conf"
# Reference: podman-build(1)
# shellcheck disable=SC2034
readonly PODMAN_BUILD_CONTEXT_CONTAINER_IMAGE="container-image://"
# Reference: podman-build(1)
# shellcheck disable=SC2034
readonly PODMAN_BUILD_CONTEXT_CONTAINER_IMAGE_DOCKER_IMAGE="docker-image://"
# Reference: podman-build(1)
# shellcheck disable=SC2034
readonly PODMAN_BUILD_CONTEXT_CONTAINER_IMAGE_DOCKER="docker://"
# shellcheck disable=SC2034
readonly PODMAN_BUILD_LOCAL_REGISTRY="localhost"
# shellcheck disable=SC2034
readonly PODMAN_BUILD_REMOTE_REGISTRY="docker.io"
# shellcheck disable=SC2034
readonly PODMAN_BUILD_IMAGE_TAG_LATEST="latest"

# podman_build()
#
# Appends default build options (--format=docker, --build-arg=BUILD_THREADS)
# to the caller-supplied options array, then runs `podman build` with those
# options and the given context directory.
#
# Arguments:
#   $1   Nameref; array of podman build options to append to and pass.
#   $2   String; path to the container build context directory.
# Outputs:
#   Writes `podman build`'s stdout/stderr, plus info/log_debug log lines.
# Returns:
#   `podman build`'s exit status.
podman::build() {
  local -n build_opts="$1"
  local ctx_dir="$2"

  log_info "Appending default podman build options."

  local -r opt_format_docker="--format=docker"
  log_info "Adding option: ${opt_format_docker}"
  build_opts+=("${opt_format_docker}")

  local -r opt_build_threads="--build-arg=BUILD_THREADS=$(nproc)"
  log_info "Adding option: ${opt_build_threads}"
  build_opts+=("${opt_build_threads}")

  log_debug "build_opts=${build_opts[*]}"
  log_debug "ctx_dir=${ctx_dir}"
  log_info "Starting podman build now."

  # TODO add this command to an array, then execute the array string
  # Allows:
  #   * printing the command before running it
  #   * Passing the cmd array on to a function to exec the command
  #     (See examples in btrfsmaintenance)
  podman build \
    "${build_opts[@]:-}" \
    "${ctx_dir}"
}

# add_build_arg_file()
#
# Appends a --build-arg-file option to the options array when ${ARGFILE_CONF}
# exists in the build context directory.  Logs a warning and returns without
# modifying the array if the file is absent.
#
# Globals:
#   context      String; build context directory, set by the calling function.
#   ARGFILE_CONF String; build-arg-file basename to look for under context.
# Arguments:
#   $1   Nameref; array of podman build options to append to.
# Outputs:
#   Warns to stderr if the build-arg file is not found.
# Returns:
#   0 always (a missing build-arg file is not treated as an error).
podman::build_add_arg_file() {
  local -n opts="$1"

  local -r build_arg_file_value="${context}/${ARGFILE_CONF}"
  if [[ ! -f "${build_arg_file_value}" ]]; then
    log_warn "Build arg file not found: ${build_arg_file_value}." \
      "No ${ARGFILE_CONF} will be added to build options."
    return 0
  fi

  local -r opt_build_arg_file="--build-arg-file"
  local -r build_arg_file="${opt_build_arg_file}=${build_arg_file_value}"

  log_info "Adding option: ${build_arg_file}"
  opts+=("${build_arg_file}")
}

# load_podman_build_env()
#
# Sources the per-image .env file and populates build_args_out, build_contexts_out,
# and image_tag_primary_out from the variables it defines (BUILD_ARGS, BUILD_CONTEXTS,
# IMAGE_TAG_PRIMARY / IMAGE_TAG_LATEST).
#
# Globals:
#   BUILD_ENV_BASE   String; base directory containing per-image .env files.
# Arguments:
#   $1   String; image name used to locate ${BUILD_ENV_BASE}/${image}.env.
#   $2   Nameref; associative array to receive BUILD_ARGS entries.
#   $3   Nameref; associative array to receive BUILD_CONTEXTS entries.
#   $4   Nameref; string to receive the primary tag.
# Outputs:
#   Writes info/warn/log_debug log lines describing what was loaded.
# Returns:
#   Non-zero (via fatal) if the per-image .env file does not exist.
podman::build_load_env() {
  local -r image="$1"
  local -n build_args_out="$2"
  local -n build_contexts_out="$3"
  local -n image_tag_primary_out="$4"

  local -r build_env="${BUILD_ENV_BASE}/${image}.env"
  [[ -f "${build_env}" ]] || log_fatal --status=5 "${build_env} file not found."

  log_info "Sourcing ${build_env}"
  # example.env is passed to shellcheck to provide dummy IDE descriptions for referenced variables
  # shellcheck source=/dev/null
  . "${build_env}"

  local i
  if [[ -n "${BUILD_ARGS[*]:-}" ]]; then
    log_info "BUILD_ARGS is set in ${build_env}. Using build-args: ${BUILD_ARGS[*]}"

    for i in "${!BUILD_ARGS[@]}"; do
      build_args_out+=(["${i}"]="${BUILD_ARGS["${i}"]}")
      log_debug "build_args_out+=([${i}]=${BUILD_ARGS[${i}]})"
    done
  else
    log_warn "BUILD_ARGS not set in ${build_env}. No additional build-args will be used."
  fi

  if [[ -n "${BUILD_CONTEXTS[*]:-}" ]]; then
    log_info "BUILD_CONTEXTS is set in ${build_env}. Keys and values will be added to "

    for i in "${!BUILD_CONTEXTS[@]}"; do
      build_contexts_out+=(["${i}"]="${BUILD_CONTEXTS["${i}"]}")
      log_debug "build_contexts_out+=[${i}]=${BUILD_CONTEXTS[${i}]})"
    done
  else
    log_warn "BUILD_CONTEXTS not set in ${build_env}. No additional build-contexts will be used."
  fi

  if [[ -v IMAGE_TAG_PRIMARY ]]; then
    log_info "IMAGE_TAG_PRIMARY is set in ${build_env}." \
      "The final image built will be tagged: ${IMAGE_TAG_PRIMARY}"
    image_tag_primary_out="${IMAGE_TAG_PRIMARY}"
    log_debug "image_tag_primary_out=${IMAGE_TAG_PRIMARY}"
  else
    log_warn "IMAGE_TAG_PRIMARY is unset in ${build_env}." \
      "The final image built will be tagged with ${IMAGE_TAG_LATEST}"
    # shellcheck disable=SC2034
    image_tag_primary_out="${IMAGE_TAG_LATEST}"
    log_debug "image_tag_primary_out=${IMAGE_TAG_LATEST}"
  fi
}

# add_build_primary_tag()
#
# Appends a --tag option in the form --tag=<local_repo>/<image>:<tag> to the
# options array.
#
# TODO separate this into its own build.sh library file
#
# Arguments:
#   $1   Nameref; array of podman build options to append to.
#   $2   String; local container repository prefix.
#   $3   String; image name.
#   $4   String; image tag.
# Outputs:
#   Writes info/log_debug log lines describing the tag option added.
podman::build_add_primary_tag() {
  # shellcheck disable=SC2178
  local -n opts="$1"
  local -r local_repo="$2"
  local -r image="$3"
  local -r tag="$4"

  local -r opt_tag="--tag"
  local -r option_image_tag="${opt_tag}=${local_repo}/${image}:${tag}"
  log_debug "option_image_tag=${option_image_tag}"

  log_info "Adding option: ${option_image_tag}"
  opts+=("${option_image_tag}")
}

# add_build_options()
#
# Iterates over an associative array of key=value pairs and appends
# <option>=<key>=<value> entries to the options array.
#
# TODO separate this into its own build.sh library file
#
# Arguments:
#   $1   Nameref; array to append to.
#   $2   Nameref; associative array of option key/value pairs.
#   $3   String; option prefix (e.g. "--build-arg").
# Outputs:
#   Writes info/log_debug log lines for each option added.
podman::build_add_options() {
  # shellcheck disable=SC2178
  local -n opts="$1"
  local -n additional_opts="$2"
  local option="$3"

  local opt_value new_build_opt
  for opt_value in "${!additional_opts[@]}"; do
    new_build_opt="${option}=${opt_value}=${additional_opts["${opt_value}"]}"
    log_debug "new_build_opt=${new_build_opt}"

    log_info "Adding option: ${new_build_opt}"
    opts+=("${new_build_opt}")
  done
}

# add_build_args()
#
# Convenience wrapper around add_build_options for --build-arg options.
#
# TODO separate this into its own build.sh library file
#
# Arguments:
#   $1   Nameref; array to append to.
#   $2   Nameref; associative array of build-arg key/value pairs.
podman::build_add_args() {
  local -r opt_build_arg="--build-arg"

  podman::build_add_options "$1" \
    "$2" \
    "${opt_build_arg}"
}

# add_build_additional_contexts()
#
# Convenience wrapper around add_build_options for --build-context options.
#
# TODO separate this into its own build.sh library file
#
# Arguments:
#   $1   Nameref; array to append to.
#   $2   Nameref; associative array of build-context key/value pairs.
podman::build_add_additional_contexts() {
  local -r opt_build_context="--build-context"

  podman::build_add_options "$1" \
    "$2" \
    "${opt_build_context}"
}

# add_container_files_ordered()
#
# Discovers all files matching Containerfile* under the given context directory,
# sorts them by version, and appends --file=<path> options to the options array.
# Skips auto-discovery if the caller already supplied -f or --file options.
#
# Arguments:
#   $1   Nameref; array to append --file options to.
#   $2   String; context directory path to search for Containerfiles.
# Outputs:
#   Writes info/log_warn log lines; warns to stderr and skips discovery if the
#   caller already supplied -f/--file options.
# Returns:
#   0 always.
podman::build_add_container_files_ordered() {
  # shellcheck disable=SC2178
  local -n opts="$1"
  local ctx="$2"

  if [[ ${opts[*]} =~ ('-f'|'--file') ]]; then
    log_warn "User provided Containerfiles found. Skipping addition of" \
      "container files. NO Containerfiles will be added from ${ctx}"
    return 0
  fi

  # TODO Save containerfile list as a variable to log here. Pass this
  # variable to mapfile.
  # log_info "Building with Containerfiles: "
  log_info "Gathering Containerfile(s) from context directory: ${ctx}"
  log_warn "Container files will be processed in version order."
  local -r containerfile="Containerfile"
  local -r opt_file="--file"
  mapfile -t -O "${#opts[@]}" "$1" < <(
    find "${ctx}" \
      -iname "${containerfile}*" \
      -printf "${opt_file}=%p\n" \
    | sort --sort=version
  )
}

# build_context_get()
#
# Pops the last element of the options array as the build context directory,
# validates that it exists, and assigns it to the ctx nameref.
#
# Arguments:
#   $1   Nameref; array whose last element is the context directory path.
#   $2   Nameref; string that receives the extracted context directory path.
# Outputs:
#   Writes an log_info log line with the resolved context directory.
# Returns:
#   Non-zero (via fatal) if the context directory does not exist.
podman::build_context_get() {
  # shellcheck disable=SC2178
  local -n opts="$1"
  local -n ctx="$2"

  ctx="${opts[0]}"
  [[ -d "${ctx}" ]] || log_fatal "Context directory not found: ${ctx}"
  unset "opts[-1]"

  log_info "Container build context directory: ${ctx}"
}

# log_image_tags()
#
# Logs each tag in the provided array at LOG_LEVEL_INFO.
#
# Arguments:
#   $1   Nameref; array of image tag strings to log.
# Outputs:
#   Writes an log_info log line per tag.
podman::log_image_tags() {
  local -n tags="$1"

  log_info "The image will be tagged with the following:"
  local t
  for t in "${tags[@]}"; do
    log_info "--tag=${t}"
  done
}

# podman_build_with_options()
#
# Orchestrates a full podman build: loads the per-image env file, adds build
# args, build contexts, the primary tag, Containerfiles, and an optional
# build-arg-file, then delegates to podman_build().
#
# Arguments:
#   $1   Nameref; caller-supplied array of additional podman build options.
#   $2   String; image name (used to locate the .env file and tag the image).
#   $3   String; build context directory path.
# Outputs:
#   Writes `podman build`'s stdout/stderr, plus info/warn/log_debug log lines.
# Returns:
#   `podman build`'s exit status; non-zero (via fatal) on earlier failures.
podman::build_with_options() {
  local -r image="$2"
  local -r context="$3"

  # shellcheck disable=SC2034
  local -A build_args
  # shellcheck disable=SC2034
  local -A build_contexts
  local image_tag_primary
  podman::build_load_env "${image}" \
    build_args \
    build_contexts \
    image_tag_primary

  podman::build_add_args "$1" build_args
  podman::build_add_additional_contexts "$1" build_contexts

  podman::build_add_primary_tag "$1" \
    "${LOCAL_REPOSITORY}" \
    "${image}" \
    "${image_tag_primary:-$PODMAN_BUILD_IMAGE_TAG_LATEST}"

  podman::add_container_files_ordered "$1" "${context}"
  podman::build_add_arg_file "$1"

  podman::build "$1" \
    "${context}"
}

if [[ "${__BASHKIT_LIB_CORE_CONTRACT_UTILS_SOURCED:-}" != "true" ]]; then
  # shellcheck source=../core/contract-utils.sh
  . "${BASH_SOURCE[0]%/*}/../core/contract-utils.sh"
fi
