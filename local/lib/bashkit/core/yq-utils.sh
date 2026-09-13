# shellcheck shell=bash

readonly __BASHKIT_LIB_CORE_YQ_UTILS_SOURCED="true"

# core::require_operands is intentionally not used here in the event that test_output is empty string.
core::yq_validate_output() {
  log_debug "Starting ${FUNCNAME[0]}()"
  local -r test_output="${1?"test_output=\$1 is required."}"
  local -r yaml_key="${2?"yaml_key=\$2 is required."}"
  local -r yaml_file="${3:-'[No file provided]'}"

  [[ -n "${test_output:-}" ]] || {
    log_error "${yaml_file} - ${yaml_key} is empty string."
    return 1
  }

  [[ "${test_output}" != "null" ]] || {
      log_error "${yaml_file} - has no ${yaml_key}"
      return 1
  }
}

if ! declare -f init_logger >/dev/null 2>&1; then
  # logging.sh should already be sourced by now.
  # This is primarily present to provide shellcheck function definitions.
  #
  # shellcheck source=../../../../../bash-logger/logging.sh
  . "${BASH_SOURCE[0]%/*}/../../../../../bash-logger/logging.sh"

  init_logger --name "$(basename "$0")"
fi

