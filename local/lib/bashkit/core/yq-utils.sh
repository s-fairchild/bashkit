# shellcheck shell=bash

# shellcheck source=../core/contract-utils.sh
. /dev/null
import core/contract-utils.sh
# shellcheck source=../../../bin/yq
. /dev/null
import ../../../bin/yq

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
