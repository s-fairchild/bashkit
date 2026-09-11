# shellcheck shell=bash
#
# ECC private-key and self-signed-certificate generation helpers built on
# openssl: openssl::private_key_gen, openssl::self_signed_cert_gen.

[[ "${XTRACE:-0}" -eq 1 ]] && set -x

readonly __BASHKIT_LIB_OPENSSL_CERT_UTILS_SOURCED="true"

# openssl::private_key_gen()
#
# Generates an ECC (prime256v1) private key with openssl.
#
# Globals:
#   None.
# Arguments:
#   None.
# Outputs:
#   The generated private key (PEM) on stdout.
# Returns:
#   The exit status of `openssl ecparam`.
openssl::private_key_gen() {
  log_debug "Starting ${FUNCNAME[0]}()"

  openssl ecparam \
    -name prime256v1 \
    -genkey
}

# openssl::usage_self_signed_cert_gen()
#
# Prints usage to stderr.
openssl::usage_self_signed_cert_gen() {
  cat <<USAGE >&2
Usage: openssl::self_signed_cert_gen [-d days] [-c country] [-s state_or_province] [-l locality] [-o organization] [-n common_name] [-a san_value]... [-h] < private_key

Generates a self-signed certificate for the ECC private key read from stdin.
The Subject Alternative Names always include "DNS:<common_name>" and
"DNS:*.<common_name>" (derived from -n); -a appends additional SAN values
to that list.

Options:
  -d days               Certificate expiration, in days. (default: 1825)
  -c country            Subject "C" (country) field. (default: "")
  -s state_or_province  Subject "ST" (state/province) field. (default: "")
  -l locality           Subject "L" (locality) field. (default: "")
  -o organization       Subject "O" (organization) field. (default: "")
  -n common_name        Subject "CN" (common name) field; also seeds the SAN
                         list (see above). (default: "")
  -a san_value          Additional Subject Alternative Name value to append
                         (e.g. "DNS:example.local"). May be specified
                         multiple times.
  -h                    Print this usage message and exit.
USAGE
}

# openssl::self_signed_cert_gen()
#
# Generates a self-signed certificate for the ECC private key read from
# stdin. The certificate subject is assembled from -c/-s/-l/-o/-n. The
# Subject Alternative Names always include "DNS:<common_name>" and
# "DNS:*.<common_name>" (derived from -n); -a appends additional SAN
# values to that list.
#
# Globals:
#   ERROR_OPTION_ARG_REQUIRED, ERROR_OPTION_UNKNOWN
# Arguments:
#   -d days               Certificate expiration, in days. (default: 1825)
#   -c country            Subject "C" field. (default: "")
#   -s state_or_province  Subject "ST" field. (default: "")
#   -l locality           Subject "L" field. (default: "")
#   -o organization       Subject "O" field. (default: "")
#   -n common_name        Subject "CN" field; also seeds the SAN list.
#                         (default: "")
#   -a san_value          Additional Subject Alternative Name value to
#                         append. Repeatable.
#   -h                    Print usage and return 0.
# Outputs:
#   The generated certificate (PEM) on stdout.
# Returns:
#   1 if stdin is empty or option-parsing fails.
openssl::self_signed_cert_gen() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  local -r input="$(cat)"
  [[ -z "${input:-}" ]] && log_fatal "Private key must be provided via stdin."

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
  san_values+=("DNS:${common_name}" "DNS:*.${common_name}")
  local -r addext="subjectAltName=$(IFS=','; printf '%s' "${san_values[*]}")"

  log_info "Generating x509 self signed certificate."
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
