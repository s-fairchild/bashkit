# shellcheck shell=bash
#
# Umbrella loader for bashkit/local/lib/bashkit/openssl library files.

if [[ "${__BASHKIT_LIB_OPENSSL_CERT_UTILS_SOURCED:-}" != "true" ]]; then
  # shellcheck source=cert-utils.sh
  . "${BASH_SOURCE[0]%/*}/cert-utils.sh"
fi
