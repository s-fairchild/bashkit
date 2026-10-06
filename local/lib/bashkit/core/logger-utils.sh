# shellcheck shell=bash
#
# Locates, sources, and initializes the external bash-logger library
# (bash-logger/logging.sh) for bashkit libraries and wrappers through
# core::logger_init, using the private helpers core::_logger_source and
# core::_logger_config_path. Also holds core::logger_resolve and
# core::print_stack_trace, which must work before the logger is loaded, and
# the __BASHKIT_CORE_ERROR_* message constants.
#
# Everything here may run before the logger exists, so errors go to stderr
# via `echo` rather than the logging API. The only dependency is
# boolean-utils.sh (core::logger_init reads BASHKIT_VERBOSE and
# BASHKIT_QUIET with it), which follows the same rule. Don't add others,
# since contract-utils.sh sources this file.

readonly __BASHKIT_LIB_CORE_LOGGER_UTILS_SOURCED="true"

# Message fragments for log lines, e.g. "-${OPTARG} ${..._OPTION_UNKNOWN}" in
# a getopts error arm. They live here rather than in contract-utils.sh so
# that every file that loads the logger has them.
readonly __BASHKIT_CORE_ERROR_FILE_NOT_FOUND="file not found"
readonly __BASHKIT_CORE_ERROR_DIR_NOT_FOUND="directory not found"
readonly __BASHKIT_CORE_ERROR_FAILED_TO_CREATE_DIR="failed to create directory"
readonly __BASHKIT_CORE_ERROR_FAILED_TO_CREATE_FILE="failed to create file"
readonly __BASHKIT_CORE_ERROR_FILE_SOURCE_FAILED="failed to source file"
readonly __BASHKIT_CORE_ERROR_OPTION_REQUIRED="option must be provided"
readonly __BASHKIT_CORE_ERROR_OPTION_UNKNOWN="option is unknown"
readonly __BASHKIT_CORE_ERROR_OPTION_ARG_DUP="[option_argument] can only be specified once"
readonly __BASHKIT_CORE_ERROR_OPTION_ARG_REQUIRED="[option argument] is required"
readonly __BASHKIT_CORE_ERROR_OPTION_OPERAND_MISSING="value must be provided"
readonly __BASHKIT_CORE_ERROR_VAR_UNSET="variable is unset"
readonly __BASHKIT_CORE_WARN_VAR_UNSET="${__BASHKIT_CORE_ERROR_VAR_UNSET}"
readonly __BASHKIT_CORE_ERROR_ARRAY_NO_INDEX="array has no indexes set"
readonly __BASHKIT_CORE_ERROR_OPERAND_REQUIRED="operand is required"
readonly __BASHKIT_CORE_ERROR_STRING_EMPTY="string cannot be empty"
readonly __BASHKIT_CORE_ERROR_STDIN_NULL="stdin cannot be null"
readonly __BASHKIT_CORE_ERROR_REGEX_FAIL="failed regex match"

# Where core::_logger_source looks for logging.sh, highest priority first.
# The first two are relative to this file
# (<bashkit>/local/lib/bashkit/core/).
readonly -a __BASHKIT_CORE_LOGGER_PATHS=(
  # bashkit's own submodule: <bashkit>/vendor/bash-logger/
  "${BASH_SOURCE[0]%/*}/../../../../vendor/bash-logger/logging.sh"
  # A copy vendored beside bashkit: <bashkit>/../bash-logger/ (e.g. forge's
  # hack/vendor/bash-logger/ next to hack/vendor/bashkit/)
  "${BASH_SOURCE[0]%/*}/../../../../../bash-logger/logging.sh"
  "${HOME:-}/.local/lib/bash-logger/logging.sh"
  "/usr/local/lib/bash-logger/logging.sh"
  "/usr/lib/bash-logger/logging.sh"
)

# Where core::_logger_config_path looks for config files, highest priority
# first, after BASHKIT_LOG_CONFIG_DIR. The first two are relative to this
# file (<bashkit>/local/lib/bashkit/core/), so a checkout or vendored copy
# uses its own configs. Installed copies have neither and fall through to
# the user and system directories.
readonly -a __BASHKIT_CORE_LOGGER_CONFIG_DIRS=(
  # bashkit's own configs: <bashkit>/.bashkit/
  "${BASH_SOURCE[0]%/*}/../../../../.bashkit"
  # A consumer's configs two levels above bashkit: <bashkit>/../../etc/bashkit/
  # (e.g. forge's hack/etc/bashkit/ for hack/vendor/bashkit/)
  "${BASH_SOURCE[0]%/*}/../../../../../../etc/bashkit"
  "${XDG_CONFIG_HOME:-${HOME:-}/.config}/bashkit"
  "/usr/local/etc/bashkit"
  "/etc/bashkit"
)

# core::_echo_stderr(message...)
#
# The fallback core::logger_resolve returns when bash-logger isn't loaded.
#
# Globals:
#   None.
# Arguments:
#   $@   The message; the operands are joined with spaces.
# Outputs:
#   The message to stderr.
# Returns:
#   The status of `echo`.
core::_echo_stderr() {
  echo "$*" >&2
}

# core::logger_resolve([level])
#
# Prints the command to log a message at <level>: `log_<level>` if
# bash-logger has defined it, otherwise core::_echo_stderr. Pass the command
# a single message string, since bash-logger's log_* functions print only
# their first operand. Either way the line goes to stderr: the fallback
# writes there itself, and core::logger_init sets `--stderr-level DEBUG`:
#
#   local logger
#   logger="$(core::logger_resolve error)"
#   "${logger}" "message"
#
# Globals:
#   None.
# Arguments:
#   $1   Optional. The bash-logger level, e.g. debug, info, warn, error.
#        Defaults to info.
# Outputs:
#   The command name on stdout.
# Returns:
#   Always 0.
core::logger_resolve() {
  if declare -f log_debug >/dev/null 2>&1; then
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))" 1>&2
  fi
  local -r level="${1:-info}"

  local logger_out
  if declare -f "log_${level}" >/dev/null 2>&1; then
    logger_out="log_${level}"
  else
    logger_out="core::_echo_stderr"
  fi
  readonly logger_out

  printf "%s" "${logger_out}"
}

# core::print_stack_trace([message])
#
# Logs <message>, if given, and then the current bash call stack at
# LOG_LEVEL_ERROR, deepest frame first (starting at this function's caller),
# so a failed contract check -- e.g. core::require_operands -- shows every
# calling function up to the entry-point script instead of just the one-line
# error. Safe to call from any function; each frame is logged as
# "at FUNCNAME (BASH_SOURCE:line)", where "line" is the line in that frame
# where it called into the next-deeper frame.
#
# The lines are collected first and reach stderr in a single write(2), so
# the report stays in one piece when other processes (background jobs,
# pipeline stages) log to the same stderr at the same time. Pass the error
# as <message> instead of logging it separately, so it can't be separated
# from its trace. bash-logger still appends to its log file and the journal
# one line at a time.
#
# Globals:
#   FUNCNAME, BASH_SOURCE, BASH_LINENO
# Arguments:
#   $@   Optional. The error message; the operands are joined with spaces.
# Outputs:
#   The message and the call stack, one frame per line, at ERROR level.
# Returns:
#   Always 0.
core::print_stack_trace() {
  # TODO switch this to log_debug or another facility?
  local logger
  logger="$(core::logger_resolve error)"
  readonly logger

  # Only stderr is captured; fd 3 keeps stdout as it was, because
  # bash-logger's `color = auto` tests whether stdout is a terminal.
  local -i i
  local report
  {
    report="$(
      {
        if (( $# > 0 )); then
          "${logger}" "$*"
        fi
        "${logger}" "Stack trace (most recent call first):"
        for (( i = 1; i < ${#FUNCNAME[@]}; i++ )); do
          "${logger}" "  at ${FUNCNAME[${i}]} (${BASH_SOURCE[${i}]}:${BASH_LINENO[$((i - 1))]})"
        done
      } 2>&1 1>&3
    )"
  } 3>&1
  readonly report

  # Not printf/echo: bash's builtins flush at every newline, which would be
  # one write per line again. `cat` copies the here-string in one write.
  if [[ -n "${report}" ]]; then
    cat >&2 <<<"${report}"
  fi
  return 0
}

# core::_logger_source()
#
# Private; core::logger_init calls it. Sources bash-logger's logging.sh from
# the first location that has a readable copy, in priority order:
#
#   1. bashkit's vendored submodule: <bashkit>/vendor/bash-logger/logging.sh
#   2. A copy vendored beside bashkit: <bashkit>/../bash-logger/logging.sh
#   3. The user install:    ~/.local/lib/bash-logger/logging.sh
#   4. The local install:   /usr/local/lib/bash-logger/logging.sh
#   5. The system install:  /usr/lib/bash-logger/logging.sh
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
core::_logger_source() {
  declare -f log_debug >/dev/null 2>&1 && log_debug "Starting ${FUNCNAME[0]}()"

  declare -f init_logger >/dev/null 2>&1 && return 0

  local candidate
  for candidate in "${__BASHKIT_CORE_LOGGER_PATHS[@]}"; do
    if [[ -f "${candidate}" && -r "${candidate}" ]]; then
      # logging.sh assigns its globals without `declare`, so sourcing it
      # from inside this function still defines them globally.
      #
      # shellcheck source=/dev/null
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

# core::_logger_env_is_valid(name)
#
# Private. Tests whether <name> can be used as an environment name
# (BASHKIT_ENV). The name becomes part of a file name (logging-<name>.conf,
# <name>.log), so `/` and `..` are rejected: it must not be able to point
# outside the directory that file belongs in.
#
# Globals:
#   None.
# Arguments:
#   $1   The environment name.
# Outputs:
#   None.
# Returns:
#   0 if <name> is letters, digits, `.`, `_`, and `-` only, doesn't start
#   with `.` or `-`, and holds no `..`; 1 otherwise.
core::_logger_env_is_valid() {
  if declare -f log_debug >/dev/null 2>&1; then
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))" 1>&2
  fi

  local -r name="${1:-}"
  local -r regex='^[A-Za-z0-9_][A-Za-z0-9._-]*$'

  [[ "${name}" =~ ${regex} && "${name}" != *..* ]]
}

# core::_logger_config_path()
#
# Private; core::logger_init calls it. Chooses a bash-logger config file
# (`init_logger --config`) from the environment and prints its path. The
# first match wins:
#
#   1. BASHKIT_LOG_CONFIG is set: that file. It must exist.
#   2. BASHKIT_ENV is set (e.g. dev, test, ci, staging, prod):
#      logging-${BASHKIT_ENV}.conf from the config directories below. One
#      of them must have it.
#   3. Neither is set: logging.conf from the config directories below, if
#      one has it.
#
# The config directories are searched in this order, so a file in an
# earlier one overrides the same file in a later one:
#
#   1. BASHKIT_LOG_CONFIG_DIR, if set (e.g. a consumer repo's own configs)
#   2. <bashkit>/.bashkit, the configs in this bashkit checkout
#   3. <bashkit>/../../etc/bashkit (e.g. forge's hack/etc/bashkit)
#   4. ${XDG_CONFIG_HOME:-~/.config}/bashkit (user; `make install` copies
#      .bashkit/ here)
#   5. /usr/local/etc/bashkit (local system)
#   6. /etc/bashkit (system)
#
# Prints nothing and succeeds when no config applies, so the caller falls
# back to bash-logger's defaults.
#
# Globals:
#   BASHKIT_LOG_CONFIG       Optional. Explicit path to a config file.
#   BASHKIT_ENV              Optional. Environment name; letters, digits,
#                            `.`, `_`, and `-` only.
#   BASHKIT_LOG_CONFIG_DIR   Optional. A directory searched before the
#                            defaults.
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
core::_logger_config_path() {
  if declare -f log_debug >/dev/null 2>&1; then
    log_debug "Starting ${FUNCNAME[0]}()" 1>&2
  fi

  local -r explicit_config="${BASHKIT_LOG_CONFIG:-}"

  if [[ -n "${explicit_config}" ]]; then
    [[ -r "${explicit_config}" ]] && { printf '%s\n' "${explicit_config}"; return 0; }

    core::print_stack_trace \
      "${FUNCNAME[0]}(): BASHKIT_LOG_CONFIG is not a readable file:" \
      "${explicit_config}"
    return 1
  fi

  local -a dirs=()
  if [[ -n "${BASHKIT_LOG_CONFIG_DIR:-}" ]]; then
    dirs+=("${BASHKIT_LOG_CONFIG_DIR}")
  fi
  dirs+=("${__BASHKIT_CORE_LOGGER_CONFIG_DIRS[@]}")
  readonly dirs

  local -r _env="${BASHKIT_ENV:-}"
  local conf="logging.conf"
  if [[ -n "${_env}" ]]; then
    # So that BASHKIT_ENV can't point outside the config dirs.
    if ! core::_logger_env_is_valid "${_env}"; then
      core::print_stack_trace \
        "${FUNCNAME[0]}(): BASHKIT_ENV is not a valid environment name:" \
        "${_env}"
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

# core::_logger_log_file_path()
#
# Private; core::logger_init calls it. Chooses the file that log lines are
# also written to (`init_logger --log`) from the environment and prints its
# path. The first match wins:
#
#   1. BASHKIT_LOG_FILE is set: that file.
#   2. BASHKIT_LOG_DIR is set: ${BASHKIT_ENV}.log in that directory, or
#      bashkit.log when BASHKIT_ENV isn't set.
#
# The file name is put together here, each time a script starts, and not
# where BASHKIT_LOG_DIR is exported. An .envrc is evaluated once, when
# direnv loads it, so a file name built there would still be the old one
# under `BASHKIT_ENV=test ./script`.
#
# Prints nothing and succeeds when neither variable is set, so that nothing
# is logged to a file.
#
# Globals:
#   BASHKIT_LOG_FILE   Optional. Explicit path to the log file.
#   BASHKIT_LOG_DIR    Optional. The directory of the per-environment log
#                      files.
#   BASHKIT_ENV        Optional. Environment name; see
#                      core::_logger_env_is_valid.
# Arguments:
#   None.
# Outputs:
#   The log file's path on stdout, if one applies. An error and stack trace
#   to stderr if BASHKIT_ENV can't be used in a file name.
# Returns:
#   1 if BASHKIT_LOG_DIR is used and BASHKIT_ENV isn't a valid environment
#   name; 0 otherwise.
core::_logger_log_file_path() {
  if declare -f log_debug >/dev/null 2>&1; then
    log_debug "Starting ${FUNCNAME[0]}()" 1>&2
  fi

  if [[ -n "${BASHKIT_LOG_FILE:-}" ]]; then
    printf '%s\n' "${BASHKIT_LOG_FILE}"
    return 0
  fi

  local -r dir="${BASHKIT_LOG_DIR:-}"
  [[ -n "${dir}" ]] || return 0

  local -r _env="${BASHKIT_ENV:-}"
  if [[ -n "${_env}" ]] && ! core::_logger_env_is_valid "${_env}"; then
    core::print_stack_trace \
      "${FUNCNAME[0]}(): BASHKIT_ENV is not a valid environment name:" \
      "${_env}"
    return 1
  fi

  printf '%s\n' "${dir%/}/${_env:-bashkit}.log"
}

# core::logger_init([init_logger options...])
#
# Loads and initializes bash-logger for a bashkit file, unless the logger is
# already loaded; a consumer that loaded it keeps its own setup. Checks the
# environment first, so a bad value fails before anything is sourced and a
# later call can try again. Then sources the logger with
# core::_logger_source and calls `init_logger` with, in this order:
#
#   - `--verbose`, when BASHKIT_VERBOSE is true (see core::bool_is_true);
#   - `--quiet`, when BASHKIT_QUIET is true;
#   - `--level "${BASHKIT_LEVEL}"`, when BASHKIT_LEVEL is set. `--verbose`
#     also sets the level (to DEBUG), so BASHKIT_LEVEL wins over it;
#   - `--config <file>`, when core::_logger_config_path picks one;
#   - `--log <file>`, when core::_logger_log_file_path picks one:
#     BASHKIT_LOG_FILE, or ${BASHKIT_ENV}.log in BASHKIT_LOG_DIR. A config
#     file's `log_file` must be an absolute path, so a per-checkout path
#     (like the directory bashkit's .envrc sets) has to come from the
#     environment;
#   - `--name <file>`, the basename of the file that called this function;
#   - `--stderr-level DEBUG`, so log lines never end up in a caller's
#     `$(...)` capture;
#   - the operands, passed through (e.g. `--name "$(basename "$0")"`).
#
# bash-logger reads the config file first and then applies the other options
# in order, so each option overrides the config file and any earlier option.
# The config can't change anything set here, and an operand overrides all of
# it.
#
# Globals:
#   BASHKIT_VERBOSE    Optional. A boolean (true/false, yes/no, on/off, 1/0,
#                      any case); true logs at DEBUG. Defaults to false.
#   BASHKIT_QUIET      Optional. A boolean; true turns off console output.
#                      Defaults to false.
#   BASHKIT_LEVEL      Optional. A bash-logger level name or number (e.g.
#                      DEBUG, INFO, WARN). bash-logger uses INFO for a value
#                      it doesn't recognize.
#   BASHKIT_LOG_FILE   Optional. File to also write log lines to;
#                      bash-logger creates its directory if needed.
#   BASHKIT_LOG_DIR    Optional. Without BASHKIT_LOG_FILE, the directory to
#                      write ${BASHKIT_ENV}.log in.
#   See also core::_logger_source, core::_logger_config_path, and
#   core::_logger_log_file_path.
# Arguments:
#   $@   Optional. Extra options for `init_logger`.
# Outputs:
#   An error and stack trace to stderr if BASHKIT_VERBOSE or BASHKIT_QUIET
#   isn't a boolean, if BASHKIT_ENV isn't a valid environment name, or if
#   the logger or a requested config can't be found.
#   Whatever `init_logger` writes.
# Returns:
#   0 if the logger was already loaded; 1 if BASHKIT_VERBOSE or BASHKIT_QUIET
#   isn't a boolean; otherwise the first non-zero status of
#   core::_logger_config_path, core::_logger_log_file_path,
#   core::_logger_source, or `init_logger`.
core::logger_init() {
  declare -f init_logger >/dev/null 2>&1 && return 0

  # No entry log: the logger isn't loaded until core::_logger_source runs.

  unset LOG_FILE USE_COLORS LOG_FORMAT \
    CURRENT_LOG_LEVEL LOG_STDERR_LEVEL \
    SCRIPT_NAME USE_JOURNAL

  local -r verbose="${BASHKIT_VERBOSE:-${__BASHKIT_CORE_BOOLEAN_FALSE}}"
  local -r quiet="${BASHKIT_QUIET:-${__BASHKIT_CORE_BOOLEAN_FALSE}}"
  local -r level="${BASHKIT_LEVEL:-}"
  # BASH_SOURCE[1] is unset when this is called from an interactive shell.
  local -r caller="${BASH_SOURCE[1]:-${0}}"

  local invalid=""
  core::bool_is_valid "${verbose}" || invalid+=" BASHKIT_VERBOSE=${verbose}"
  core::bool_is_valid "${quiet}" || invalid+=" BASHKIT_QUIET=${quiet}"
  readonly invalid
  if [[ -n "${invalid}" ]]; then
    core::print_stack_trace \
      "${FUNCNAME[0]}(): expected true/false, yes/no, on/off, or 1/0:" \
      "${invalid# }"
    return 1
  fi

  # Reports its own errors, with a stack trace.
  local config
  config="$(core::_logger_config_path)" || return
  readonly config

  local log_file
  log_file="$(core::_logger_log_file_path)" || return
  readonly log_file

  core::_logger_source || return

  local -a options=()
  # Both values were checked above, so these can't return the invalid status.
  if core::bool_is_true "${verbose}"; then
    options+=("--verbose")
  fi
  if core::bool_is_true "${quiet}"; then
    options+=("--quiet")
  fi
  # After --verbose, so BASHKIT_LEVEL wins over the DEBUG level it sets.
  [[ -n "${level}" ]] && options+=("--level" "${level}")
  [[ -n "${config}" ]] && options+=("--config" "${config}")
  [[ -n "${log_file}" ]] && options+=("--log" "${log_file}")
  options+=(
    "--name" "${caller##*/}"
    "--stderr-level" "DEBUG"
    "$@"
  )
  readonly options

  init_logger "${options[@]}" || return
  log_debug "${FUNCNAME[0]}(): init_logger ${options[*]}" 1>&2
}

if [[ "${__BASHKIT_LIB_CORE_BOOLEAN_UTILS_SOURCED:-}" != "true" ]]; then
  # shellcheck source=boolean-utils.sh
  . "${BASH_SOURCE[0]%/*}/boolean-utils.sh"
fi
