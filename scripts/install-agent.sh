#!/usr/bin/env bash
#
# Download Elastic Agent from the SIEM host mirror (if needed) and enroll it.
#
# Usage:
#   sudo ./install-agent.sh \
#     --url  https://192.168.1.108:8220 \
#     --token <enrollment-token>
#
# Optional: --ca /path/to/ca.crt  --version 9.5.3  --artifacts-port 9080

set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 --url <fleet-url> --token <enrollment-token> [--ca <ca-cert>] [--version 9.5.3]

  --url              Fleet Server URL (e.g. https://192.168.1.108:8220)
  --token            Enrollment token (Kibana → Fleet → Add agent)
  --ca               CA certificate (default: download from the SIEM mirror)
  --version          Elastic Agent version (default: 9.5.3)
  --artifacts-port   Mirror port (default: 9080)
EOF
  exit 1
}

FLEET_URL="" TOKEN="" CA_PATH="" VERSION="9.5.3" ARTIFACTS_PORT="9080"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)             FLEET_URL="$2";     shift 2 ;;
    --token)           TOKEN="$2";         shift 2 ;;
    --ca)              CA_PATH="$2";       shift 2 ;;
    --version)         VERSION="$2";       shift 2 ;;
    --artifacts-port)  ARTIFACTS_PORT="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

[[ -z "$FLEET_URL" || -z "$TOKEN" ]] && usage
[[ $EUID -ne 0 ]] && { echo "Error: run this script with sudo"; exit 1; }

fetch() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$2" "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$2" "$1"
  else
    echo "Error: need curl or wget"; exit 1
  fi
}

FLEET_HOST="${FLEET_URL#*://}"
FLEET_HOST="${FLEET_HOST%%:*}"
FLEET_HOST="${FLEET_HOST%%/*}"
MIRROR="http://${FLEET_HOST}:${ARTIFACTS_PORT}"

if [[ -z "$CA_PATH" || ! -f "$CA_PATH" ]]; then
  CA_PATH="/tmp/elk-ca.crt"
  echo "==> Downloading CA from ${MIRROR}/ca.crt"
  fetch "${MIRROR}/ca.crt" "$CA_PATH"
fi

AGENT_BIN=""
if [[ -x ./elastic-agent ]]; then
  AGENT_BIN="./elastic-agent"
else
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64|Linux-amd64)   REL="linux-x86_64.tar.gz" ;;
    Linux-aarch64|Linux-arm64)  REL="linux-arm64.tar.gz" ;;
    Darwin-x86_64)              REL="darwin-x86_64.tar.gz" ;;
    Darwin-arm64)               REL="darwin-aarch64.tar.gz" ;;
    *) echo "Error: unsupported OS/arch $(uname -s) $(uname -m)"; exit 1 ;;
  esac
  ARCHIVE="elastic-agent-${VERSION}-${REL}"
  URL="${MIRROR}/downloads/beats/elastic-agent/${ARCHIVE}"
  WORK="/tmp/elastic-agent-${VERSION}"
  echo "==> Downloading Elastic Agent from ${URL}"
  mkdir -p "$WORK"
  fetch "$URL" "/tmp/${ARCHIVE}"
  tar -xzf "/tmp/${ARCHIVE}" -C "$WORK"
  AGENT_BIN="$(find "$WORK" -type f -name elastic-agent | head -1)"
  [[ -n "$AGENT_BIN" ]] || { echo "Error: elastic-agent not found in archive"; exit 1; }
  chmod +x "$AGENT_BIN"
fi

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
"$AGENT_BIN" install \
  --url="$FLEET_URL" \
  --enrollment-token="$TOKEN" \
  --certificate-authorities="$CA_PATH"

echo "==> Done. Check agent status: sudo elastic-agent status"
