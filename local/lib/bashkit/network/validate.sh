# shellcheck shell=bash
#
# Network-related validation helpers.

declare -r __vendor_bashkit_lib_network_validate_sourced="true"

# validate_url(url)
#
# Validates that a string is a well-formed http(s)/ftp/file URL.
#
# Globals:
#   ERROR_STRING_EMPTY, ERROR_REGEX_FAIL
# Arguments:
#   $1   The URL string to validate.
# Outputs:
#   An error describing the failure.
# Returns:
#   1 if the URL is empty or does not match the expected pattern; 0
#   otherwise.
validate_url() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  require_operands 1 "$@" || return 1
  local -r url="$1"

  if [[ -z "${url}" ]]; then
    error "\$1 ${ERROR_STRING_EMPTY}"
    return 1
  fi

  local -r regex='^(https?|ftp|file)://[-[:alnum:]\+&@#/%?=~_|!:,.;]*[-[:alnum:]\+&@#/%=~_|\.]*$'

  if [[ ! "${url}" =~ ${regex} ]]; then
    error "\$1 ${ERROR_REGEX_FAIL}: ${regex}"
    return 1
  fi
}

if [[ "${__bash_logger_adapter_sourced:-}" != "true" ]]; then
  declare __bash_logger_adapter_path="${BASH_SOURCE[0]%/*}/../../../../../bash-logger-adapter/adapter.sh"
  [[ -f "${__bash_logger_adapter_path}" ]] || { printf '%s\n' "failed to find file: ${__bash_logger_adapter_path}" >&2; exit 1; }
  # shellcheck source=../../../../../bash-logger-adapter/adapter.sh
  . "${__bash_logger_adapter_path}"
  unset __bash_logger_adapter_path
fi

if [[ "${__vendor_bashkit_local_lib_bashkit_options_operands_utils_sourced:-}" != "true" ]]; then
  declare __vendor_bashkit_local_lib_bashkit_options_operands_utils="${BASH_SOURCE[0]%/*}/../options-operands-utils.sh"
  [[ -f "${__vendor_bashkit_local_lib_bashkit_options_operands_utils}" ]] || fatal "${ERROR_FILE_NOT_FOUND}: ${__vendor_bashkit_local_lib_bashkit_options_operands_utils}"
  # shellcheck source=../options-operands-utils.sh
  . "${__vendor_bashkit_local_lib_bashkit_options_operands_utils}"
  unset __vendor_bashkit_local_lib_bashkit_options_operands_utils
fi
