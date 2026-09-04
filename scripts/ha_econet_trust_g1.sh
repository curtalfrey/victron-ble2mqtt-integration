#!/usr/bin/env bash
# Official EcoNet TLS workaround for Home Assistant Container 2026.7+.
# https://www.home-assistant.io/integrations/econet/#ssl-certificate-verification-failed-home-assistant-container-installs
#
# DigiCert Global Root CA (G1) was removed from the container CA bundle; Rheem
# ClearBlade still chains to it. This adds that root only. It does not disable TLS.
set -Eeuo pipefail
IFS=$'\n\t'

HA_CONFIG_DIR="${HA_CONFIG_DIR:-/opt/homeassistant}"
HA_CONT="${HA_CONT:-homeassistant}"
G1_URL="https://cacerts.digicert.com/DigiCertGlobalRootCA.crt.pem"
EXPECTED_SHA256="43:48:A0:E9:44:4C:78:CB:26:5E:05:8D:5E:89:44:B4:D8:4F:96:62:BD:26:DB:25:7F:89:34:A4:43:C7:01:61"

if ! docker inspect "$HA_CONT" >/dev/null 2>&1; then
  echo "[econet-g1] container ${HA_CONT} is not present" >&2
  exit 1
fi

mkdir -p "${HA_CONFIG_DIR}/ssl"
curl -fsSL "$G1_URL" -o "${HA_CONFIG_DIR}/ssl/digicert-global-root-ca-g1.pem"
fp="$(openssl x509 -in "${HA_CONFIG_DIR}/ssl/digicert-global-root-ca-g1.pem" -noout -fingerprint -sha256 | sed 's/^.*=//')"
if [[ "$fp" != "$EXPECTED_SHA256" ]]; then
  echo "[econet-g1] DigiCert G1 fingerprint mismatch: ${fp}" >&2
  exit 1
fi

docker exec "$HA_CONT" cat /etc/ssl/certs/ca-certificates.crt \
  > "${HA_CONFIG_DIR}/ssl/ca-bundle+g1.pem"
cat "${HA_CONFIG_DIR}/ssl/digicert-global-root-ca-g1.pem" \
  >> "${HA_CONFIG_DIR}/ssl/ca-bundle+g1.pem"

echo "[econet-g1] wrote ${HA_CONFIG_DIR}/ssl/ca-bundle+g1.pem"
echo "[econet-g1] set HA_SSL_CERT_FILE=/config/ssl/ca-bundle+g1.pem and recreate homeassistant"
