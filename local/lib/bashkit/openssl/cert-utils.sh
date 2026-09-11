# hack/lib/openssl/openssl-gen-certs.sh
#
# shellcheck shell=bash

readonly __BASHKIT_LIB_OPENSSL_CERT_UTILS_SOURCED="true"

# openssl_gen_private_key()
#
# Generates an ECC private key with openssl.
#
# Outputs:
#   The generated private key (PEM) on stdout.
openssl::private_key_gen() {
  debug "Starting ${FUNCNAME[0]}()"

  openssl ecparam \
    -name prime256v1 \
    -genkey
}

openssl::usage_self_signed_cert_gen() {
  cat <<USAGE >&2
Usage: openssl_gen_self_signed_certificate [-d days] [-s subject] [-a san_value]... [-h] < private_key

Generates a self-signed certificate for the ECC private key read from stdin.

Options:
  -d days      Certificate expiration, in days. (default: 1825)
  -s subject   Certificate subject string.
               (default: "/C=US/ST=New York/L=New York City/O=Local Ignition Server/CN=ignition.local")
  -a san_value Subject Alternative Name value to append (e.g. "DNS:example.local").
               May be specified multiple times.
               (default SAN values: "DNS:ignition.local", "DNS:*.ignition.local", "IP:127.0.0.1")
  -h           Print this usage message and exit.
USAGE
}

# openssl_gen_self_signed_certificate()
#
# Generates a self-signed certificate for the ECC private key read from stdin.
#
# Arguments:
#   -d days      Certificate expiration, in days. (default: 1825)
#   -s subject   Certificate subject string.
#   -a san_value Subject Alternative Name value to append. Repeatable.
#   -h           Print usage and return 0.
# Outputs:
#   The generated certificate (PEM) on stdout.
# Returns:
#   1 if stdin is empty or option-parsing fails.
openssl::self_signed_cert_gen() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  local -r input="$(cat)"
  [[ -z "${input:-}" ]] && fatal "Private key must be provided via stdin."

  local -i days=1825
  local -a san_values
  local country="" state_or_province="" locality="" organization="" common_name="" opt
  while getopts ':d:c:s:l:o:n:a:h' opt; do
    case "${opt}" in
      d)
        readonly days="${OPTARG}"
        log_debug "Updating Expiration Days to: ${days}"
        ;;
      c)
        readonly country="${OPTARG}"
        log_debug "$(declare -p country)"
        ;;
      s)
        readonly state_or_province="${OPTARG}"
        log_debug "$(declare -p state_or_province)"
        ;;
      l)
        readonly locality="${OPTARG}"
        log_debug "$(declare -p locality)"
        ;;
      o)
        readonly organization="${OPTARG}"
        log_debug "$(declare -p organization)"
        ;;
      n)
        readonly common_name="${OPTARG}"
        log_debug "$(declare -p common_name)"
        ;;
      a)
        readonly san_values+=("${OPTARG}")
        log_sensitive "$(declare -p san_values)"
        ;;
      h) openssl::usage_self_signed_cert_gen; return 0 ;;
      :)
        openssl::usage_self_signed_cert_gen
        log_error "-${OPTARG} ${ERROR_OPTION_ARG_REQUIRED}"
        return 1
        ;;
      ?)
        openssl::usage_self_signed_cert_gen
        log_error "-${OPTARG} ${ERROR_OPTION_UNKNOWN}"
        return 1
        ;;
    esac
  done
  shift $((OPTIND - 1))

  local -r subject="/C=${country}/ST=${state_or_province}/L=${locality}/O=${organization}/CN=${common_name}"
  local -a san_values=("DNS:${common_name}" "DNS:*.${common_name}")
  local -r addext="subjectAltName=$(IFS=','; printf '%s' "${san_values[*]}")"

  openssl req \
    -x509 \
    -nodes \
    -key /dev/stdin \
    -days "${days}" \
    -subj "${subject}" \
    -addext "${addext}" \
    -out /dev/stdout \
    <<< "${input}"
}

if ! declare -f init_logger >/dev/null 2>&1; then
  # logging.sh should already be sourced by now.
  # This is primarily present to provide shellcheck function definitions.
  #
  # shellcheck source=../../../../../bash-logger/logging.sh
  . "${BASH_SOURCE[0]%/*}/../../../../../bash-logger/logging.sh"

  init_logger --name "$(basename "$0")"
fi
