#!/usr/bin/env bash
#
# Enroll an Elastic Agent on Linux or macOS.
# Installs the stack CA into the system trust store and enrolls the agent.
#
# Usage:
#   sudo ./install-agent.sh \
#     --url  https://192.168.1.100:8220 \
#     --token <enrollment-token> \
#     --ca   /path/to/ca.crt

set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 --url <fleet-url> --token <enrollment-token> --ca <ca-cert-path>

  --url    Fleet Server URL       (e.g. https://192.168.1.100:8220)
  --token  Enrollment token       (from Kibana → Fleet → Add agent)
  --ca     Path to CA certificate (tls/certs/ca/ca.crt from the stack)
EOF
  exit 1
}

FLEET_URL="" TOKEN="" CA_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)   FLEET_URL="$2"; shift 2 ;;
    --token) TOKEN="$2";     shift 2 ;;
    --ca)    CA_PATH="$2";   shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

[[ -z "$FLEET_URL" || -z "$TOKEN" || -z "$CA_PATH" ]] && usage
[[ ! -f "$CA_PATH" ]] && { echo "Error: CA certificate not found: $CA_PATH"; exit 1; }
[[ $EUID -ne 0 ]] && { echo "Error: run this script with sudo"; exit 1; }

echo "==> Installing CA certificate into system trust store..."

if [[ -d /usr/local/share/ca-certificates ]]; then
  cp "$CA_PATH" /usr/local/share/ca-certificates/elk-ca.crt
  update-ca-certificates
  echo "    Done (Debian/Ubuntu)"
elif [[ -d /etc/pki/ca-trust/source/anchors ]]; then
  cp "$CA_PATH" /etc/pki/ca-trust/source/anchors/elk-ca.crt
  update-ca-trust
  echo "    Done (RHEL/CentOS/Fedora)"
elif command -v security &>/dev/null; then
  security add-trusted-cert -d -r trustRoot \
    -k /Library/Keychains/System.keychain "$CA_PATH"
  echo "    Done (macOS)"
else
  echo "    Warning: unknown OS — please install the CA certificate manually"
fi

echo "==> Installing Elastic Agent..."
./elastic-agent install \
  --url="$FLEET_URL" \
  --enrollment-token="$TOKEN" \
  --certificate-authorities="$CA_PATH"

echo "==> Done. Check agent status: sudo elastic-agent status"
