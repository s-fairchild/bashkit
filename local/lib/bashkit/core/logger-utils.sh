# shellcheck shell=bash
#
# Locates, sources, and initializes the external bash-logger library
# (bash-logger/logging.sh) for bashkit libraries and wrappers:
# core::logger_source, core::logger_config_path, and core::logger_init. Also
# holds the diagnostics that must work before the logger is loaded:
# core::print_stack_trace and core::init_git_submodules_error.
#
# Everything here may run before the logger exists, so errors go to stderr
# via `echo` rather than the logging API. This file has no dependencies;
# keep it that way, since contract-utils.sh sources it.

[[ "${XTRACE:-0}" -eq 1 ]] && set -x

readonly __BASHKIT_LIB_CORE_LOGGER_UTILS_SOURCED="true"

# Where core::logger_source looks for logging.sh, highest priority first.
# The vendored path is bashkit's own submodule, relative to this file:
# <bashkit>/local/lib/bashkit/core/ -> <bashkit>/vendor/bash-logger/.
readonly -a __BASHKIT_CORE_LOGGER_PATHS=(
  "${BASH_SOURCE[0]%/*}/../../../../vendor/bash-logger/logging.sh"
  "${HOME:-}/.local/lib/bash-logger/logging.sh"
  "/usr/local/lib/bash-logger/logging.sh"
)

# Where core::logger_config_path looks for config files, highest priority
# first, unless BASHKIT_LOG_CONFIG_DIR is set.
readonly -a __BASHKIT_CORE_LOGGER_CONFIG_DIRS=(
  "${BASH_SOURCE[0]%/*}/../../../../.bashkit"
  "${XDG_CONFIG_HOME:-${HOME:-}/.config}/bashkit"
  "/usr/local/etc/bashkit"
  "/etc/bashkit"
)

# core::print_stack_trace()
#
# Logs the current bash call stack at LOG_LEVEL_ERROR, deepest frame first
# (starting at this function's caller), so a failed contract check --
# e.g. core::require_operands -- shows every calling function up to the
# entry-point script instead of just the one-line error. Safe to call from
# any function; each frame is logged as "at FUNCNAME (BASH_SOURCE:line)",
# where "line" is the line in that frame where it called into the
# next-deeper frame.
#
# Globals:
#   FUNCNAME, BASH_SOURCE, BASH_LINENO
# Arguments:
#   None.
# Outputs:
#   The call stack, one frame per line, at ERROR level.
# Returns:
#   Always 0.
core::print_stack_trace() {
  local logger
  # TODO switch this to log_debug or another facility?
  if declare -f log_error >/dev/null 2>&1; then
    logger="log_error"
  else
    logger="echo"
  fi

  local -i i
  # >&2 keeps the echo fallback out of callers' $(...) captures.
  "${logger}" "Stack trace (most recent call first):" >&2
  for (( i = 1; i < ${#FUNCNAME[@]}; i++ )); do
    "${logger}" "  at ${FUNCNAME[${i}]} (${BASH_SOURCE[${i}]}:${BASH_LINENO[$((i - 1))]})" >&2
  done
}

# core::logger_source()
#
# Sources bash-logger's logging.sh from the first location that has a
# readable copy, in priority order:
#
#   1. bashkit's vendored submodule: <bashkit>/vendor/bash-logger/logging.sh
#   2. The user install:   ~/.local/lib/bash-logger/logging.sh
#   3. The system install: /usr/local/lib/bash-logger/logging.sh
#
# Does nothing if the logger is already loaded (`init_logger` is defined), so
# a consumer that loaded its own copy keeps it. Only sources the file; call
# core::logger_init (or `init_logger`) afterwards to initialize it.
#
# Globals:
#   __BASHKIT_CORE_LOGGER_PATHS
# Arguments:
#   None.
# Outputs:
#   An error and stack trace to stderr, listing every searched path, if none
#   has the logger.
# Returns:
#   0 if the logger is loaded or was sourced; 1 if no copy was found;
#   otherwise the status of sourcing logging.sh.
core::logger_source() {
  declare -f log_debug >/dev/null 2>&1 && log_debug "Starting ${FUNCNAME[0]}()"

  declare -f init_logger >/dev/null 2>&1 && return 0

  local candidate
  for candidate in "${__BASHKIT_CORE_LOGGER_PATHS[@]}"; do
    if [[ -f "${candidate}" && -r "${candidate}" ]]; then
      # logging.sh assigns its globals without `declare`, so sourcing it
      # from inside this function still defines them globally.
      #
      # shellcheck source=../../../../vendor/bash-logger/logging.sh
      . "${candidate}"
      return
    fi
  done

  # The logger isn't available, so core::fail can't be used here.
  {
    echo "${FUNCNAME[0]}(): bash-logger/logging.sh not found. Searched:"
    printf '  %s\n' "${__BASHKIT_CORE_LOGGER_PATHS[@]}"
    echo "For the vendored copy, run: git submodule update --init --recursive"
  } >&2
  core::print_stack_trace
  return 1
}

# core::logger_config_path()
#
# Chooses a bash-logger config file (`init_logger --config`) from the
# environment and prints its path. The first match wins:
#
#   1. BASHKIT_LOG_CONFIG is set: that file. It must exist.
#   2. BASHKIT_ENV is set (e.g. development, staging, production):
#      logging-${BASHKIT_ENV}.conf from the config directories below. One
#      of them must have it.
#   3. Neither is set: logging.conf from the config directories below, if
#      one has it.
#
# The config directories are BASHKIT_LOG_CONFIG_DIR if it is set.
# Otherwise they are ${XDG_CONFIG_HOME:-~/.config}/bashkit, then
# /etc/bashkit, searched in that order.
#
# Prints nothing and succeeds when no config applies, so the caller falls
# back to bash-logger's defaults.
#
# Globals:
#   BASHKIT_LOG_CONFIG       Optional. Explicit path to a config file.
#   BASHKIT_ENV              Optional. Environment name; letters, digits,
#                            `.`, `_`, and `-` only.
#   BASHKIT_LOG_CONFIG_DIR   Optional. The one directory to search, in place
#                            of the defaults.
#   __BASHKIT_CORE_LOGGER_CONFIG_DIRS
# Arguments:
#   None.
# Outputs:
#   The config file's path on stdout, if one applies. An error and stack
#   trace to stderr if BASHKIT_LOG_CONFIG or BASHKIT_ENV names a config that
#   can't be used.
# Returns:
#   1 if BASHKIT_LOG_CONFIG or BASHKIT_ENV names a config that can't be
#   used; 0 otherwise.
core::logger_config_path() {
  if declare -f log_debug >/dev/null 2>&1; then
    log_debug "Starting ${FUNCNAME[0]}()" 1>&2
  fi

  local -r explicit_config="${BASHKIT_LOG_CONFIG:-}"

  if [[ -n "${explicit_config}" ]]; then
    [[ -r "${explicit_config}" ]] && { printf '%s\n' "${explicit_config}"; return 0; }

    echo "${FUNCNAME[0]}(): BASHKIT_LOG_CONFIG is not a readable file:" \
      "${explicit_config}" >&2
    core::print_stack_trace
    return 1
  fi

  local -a dirs
  if [[ -n "${BASHKIT_LOG_CONFIG_DIR:-}" ]]; then
    dirs=("${BASHKIT_LOG_CONFIG_DIR}")
  else
    dirs=("${__BASHKIT_CORE_LOGGER_CONFIG_DIRS[@]}")
  fi
  readonly dirs

  local -r _env="${BASHKIT_ENV:-}"
  local conf="logging.conf"
  if [[ -n "${_env}" ]]; then
    # Reject `/` and `..` so BASHKIT_ENV can't point outside the config dirs.
    local -r _env_regex='^[A-Za-z0-9_][A-Za-z0-9._-]*$'
    if [[ ! "${_env}" =~ ${_env_regex} || "${_env}" == *..* ]]; then
      echo "${FUNCNAME[0]}(): BASHKIT_ENV is not a valid environment name:" \
        "${_env}" >&2
      core::print_stack_trace
      return 1
    fi
    conf="logging-${_env}.conf"
  fi
  readonly conf

  local dir
  for dir in "${dirs[@]}"; do
    [[ -r "${dir}/${conf}" ]] && { printf '%s\n' "${dir}/${conf}"; return 0; }
  done

  if [[ -n "${_env}" ]]; then
    {
      echo "${FUNCNAME[0]}(): BASHKIT_ENV=${_env}: ${conf} not found. Searched:"
      printf '  %s\n' "${dirs[@]}"
    } >&2
    core::print_stack_trace
    return 1
  fi
}

# core::logger_init([init_logger options...])
#
# Loads and initializes bash-logger for a bashkit file, unless the logger is
# already loaded; a consumer that loaded it keeps its own setup. Sources it
# with core::logger_source, then calls `init_logger` with:
#
#   - `--config <file>`, when core::logger_config_path picks one;
#   - `--stderr-level DEBUG`, so log lines never end up in a caller's
#     `$(...)` capture;
#   - the operands, passed through (e.g. `--name "$(basename "$0")"`).
#
# bash-logger applies command-line options over the config file, so the
# config can't change the stderr level or any option passed as an operand.
#
# Globals:
#   See core::logger_source and core::logger_config_path.
# Arguments:
#   $@   Optional. Extra options for `init_logger`.
# Outputs:
#   Errors to stderr if the logger or a requested config can't be found.
#   Whatever `init_logger` writes.
# Returns:
#   0 if the logger was already loaded; otherwise the first non-zero status
#   of core::logger_source, core::logger_config_path, or `init_logger`.
core::logger_init() {
  declare -f init_logger >/dev/null 2>&1 && return 0

  # No entry log: the logger isn't initialized until the end.
  core::logger_source || return

  local config
  config="$(core::logger_config_path)" || return
  readonly config

  local -a options=()
  if [[ -n "${config}" ]]; then
    options+=("--config" "${config}")
  fi
  options+=("--stderr-level" "DEBUG" "$@")
  readonly options

  init_logger "${options[@]}" || return
  log_debug "${FUNCNAME[0]}(): init_logger ${options[*]}" 1>&2
}
