# shellcheck shell=bash
#
# Umbrella loader for bashkit/local/lib/bashkit/core library files.
#
# Add new core library files to this file as they are created.

readonly __BASHKIT_LIB_CORE_SOURCED="true"

if [[ "${__BASHKIT_LIB_CORE_BIN_UTILS_SOURCED:-}" != "true" ]]; then
  # shellcheck source=bin-utils.sh
  . "${BASH_SOURCE[0]%/*}/bin-utils.sh"
fi

if [[ "${__BASHKIT_LIB_CORE_CONTRACT_UTILS_SOURCED:-}" != "true" ]]; then
  # shellcheck source=contract-utils.sh
  . "${BASH_SOURCE[0]%/*}/contract-utils.sh"
fi

if [[ "${__BASHKIT_LIB_CORE_FILE_UTILS_SOURCED:-}" != "true" ]]; then
  # shellcheck source=file-utils.sh
  . "${BASH_SOURCE[0]%/*}/file-utils.sh"
fi

if [[ "${__BASHKIT_LIB_CORE_SHA512SUM_UTILS_SOURCED:-}" != "true" ]]; then
  # shellcheck source=sha512sum-utils.sh
  . "${BASH_SOURCE[0]%/*}/sha512sum-utils.sh"
fi
