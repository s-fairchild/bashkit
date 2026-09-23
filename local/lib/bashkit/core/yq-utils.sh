# shellcheck shell=bash

readonly __BASHKIT_LIB_CORE_YQ_UTILS_SOURCED="true"

core::yq_validate_output() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  core::require_operands 2 "$@" || return
  local -r test_output="${1}"
  local -r yaml_key="${2}"
  local -r yaml_file="${3:-[No file provided]}"

  [[ -n "${test_output:-}" ]] || {
    core::fail "${yaml_file} - ${yaml_key} is empty string." \
      || return
  }

  [[ "${test_output}" != "null" ]] || {
    core::fail "${yaml_file} - has no ${yaml_key}" \
      || return
  }
}

if [[ "${__BASHKIT_LIB_CORE_CONTRACT_UTILS_SOURCED:-}" != "true" ]]; then
  # shellcheck source=../core/contract-utils.sh
  . "${BASH_SOURCE[0]%/*}/../core/contract-utils.sh"
fi

if [[ "${__BASHKIT_BIN_YQ_SOURCED:-}" != "true" ]]; then
  # shellcheck source=../../../bin/yq
  . "${BASH_SOURCE[0]%/*}/../../../bin/yq"
fi
