# shellcheck shell=bash

[[ "${XTRACE:-0}" -eq 1 ]] && set -x

readonly __BASHKIT_LIB_K3S_TOKEN_UTILS_SOURCED="true"

# k3s_gen_token_openssl()
#
# Generates a 64-character lowercase hex token using `openssl rand -hex 32`.
k3s::token_gen_openssl() {
  log_debug "Starting ${FUNCNAME[0]}()"

  openssl rand -hex 32
}

# k3s_gen_token_tr()
#
# Generates a 64-character lowercase hex token using `tr` + `head` as a
# fallback when openssl is unavailable.  head triggers SIGPIPE to tr; the
# resulting non-zero exit is suppressed.
k3s::token_gen_tr() {
  log_debug "Starting ${FUNCNAME[0]}()"

  # head triggers SIGPIPE to tr; suppress the resulting non-zero exit
  tr -dc \
    'a-f0-9' \
    < /dev/urandom \
  | head -c 64 \
  || true
}

# k3s_gen_token_shasum()
#
# Generates a 64-character lowercase hex token using sha256sum as a secondary
# fallback when neither openssl nor tr is available.
k3s::token_gen_shasum() {
  log_debug "Starting ${FUNCNAME[0]}()"

  # sha256sum produces 64 hex chars with no trailing spaces
  head -c 32 /dev/urandom \
  | sha256sum \
  | cut -d ' ' -f 1
}

# k3s_gen_token()
#
# Generates a 64-character lowercase hex token for use as a k3s cluster token.
# Tries openssl first, falls back to tr, then sha256sum.
#
# Reference: https://github.com/alexellis/k3sup#create-a-multi-master-ha-setup-with-external-sql
#
# Outputs:
#   The generated token on stdout.
# Returns:
#   The exit status of whichever generator function was used.
k3s::token_gen() {
  log_debug "Starting ${FUNCNAME[0]}()"

  local -r error_prefix="failed to generate token with"
  if which openssl > /dev/null 2>&1; then
    k3s::token_gen_openssl || log_error "${error_prefix} openssl."
  elif which tr > /dev/null 2>&1; then
    log_warn "openssl not found. Falling back to tr."
    k3s::token_gen_tr || log_error "${error_prefix} tr."
  else
    log_warn "tr not found. Falling back to shasum."
    k3s::token_gen_shasum || log_error "${error_prefix} shasum."
  fi
}

if ! declare -f init_logger >/dev/null 2>&1; then
  # logging.sh should already be sourced by now.
  # This is primarily present to provide shellcheck function definitions.
  #
  # shellcheck source=../../../../../bash-logger/logging.sh
  . "${BASH_SOURCE[0]%/*}/../../../../../bash-logger/logging.sh"

  init_logger --name "$(basename "$0")"
fi
