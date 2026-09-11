# shellcheck shell=bash
#
# Umbrella loader for bashkit/local/lib/bashkit/ignition library files.
#
# Add new ignition library files to this file as they are created.

readonly __BASHKIT_LIB_IGNITION_SOURCED="true"

if [[ "${__BASHKIT_LIB_IGNITION_BUTANE_SOURCED:-}" != "true" ]]; then
  # shellcheck source=butane.sh
  . "${BASH_SOURCE[0]%/*}/butane.sh"
fi

if [[ "${__BASHKIT_LIB_IGNITION_MERGE_SOURCED:-}" != "true" ]]; then
  # shellcheck source=merge.sh
  . "${BASH_SOURCE[0]%/*}/merge.sh"
fi

if [[ "${__BASHKIT_LIB_IGNITION_VALIDATE_SOURCED:-}" != "true" ]]; then
  # shellcheck source=ignition-validate.sh
  . "${BASH_SOURCE[0]%/*}/ignition-validate.sh"
fi

if [[ "${__BASHKIT_LIB_IGNITION_SERVE_SOURCED:-}" != "true" ]]; then
  # shellcheck source=serve.sh
  . "${BASH_SOURCE[0]%/*}/serve.sh"
fi
