# shellcheck shell=bash

[[ "${XTRACE:-0}" -eq 1 ]] && set -x

readonly __BASHKIT_LIB_CORE_CONTRACT_UTILS_SOURCED="true"

if [[ "${__BASHKIT_BIN_BW_SOURCED:-}" != "true" ]]; then
  # shellcheck source=../../../bin/bw
  . "${BASH_SOURCE[0]%/*}/../../../bin/bw"
fi

if [[ "${__BASHKIT_BIN_COREOS_INSTALLER_SOURCED:-}" != "true" ]]; then
  # shellcheck source=../../../bin/coreos-installer
  . "${BASH_SOURCE[0]%/*}/../../../bin/coreos-installer"
fi

if [[ "${__BASHKIT_BIN_YQ_SOURCED:-}" != "true" ]]; then
  # shellcheck source=../../../bin/yq
  . "${BASH_SOURCE[0]%/*}/../../../bin/yq"
fi
