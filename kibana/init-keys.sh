#!/bin/sh
set -eu

KIBANA_TEMPLATE="${KIBANA_TEMPLATE:-/kibana-template/kibana.yml}"
KIBANA_CONFIG="${KIBANA_CONFIG:-/kibana-config/kibana.yml}"

# On first run, seed the working config from the template.
# On subsequent runs, re-use the existing config to keep generated encryption keys.
# Kibana 9.5 rejects xpack.fleet package_policy `inputs.config` — re-seed if present.
if [ ! -f "$KIBANA_CONFIG" ]; then
  if [ ! -f "$KIBANA_TEMPLATE" ]; then
    echo "Error: template $KIBANA_TEMPLATE not found" >&2
    exit 1
  fi
  cp "$KIBANA_TEMPLATE" "$KIBANA_CONFIG"
  sed -i 's/\r$//' "$KIBANA_CONFIG"
  echo "Seeded config from template"
elif grep -q "elk-artifacts" "$KIBANA_CONFIG"; then
  echo "Replacing invalid Defend preconfig (Kibana 9.5); keeping encryption keys"
  grep -E '^xpack\.(security|encryptedSavedObjects|reporting)\.encryptionKey:' "$KIBANA_CONFIG" > /tmp/keys-keep.txt || true
  cp "$KIBANA_TEMPLATE" "$KIBANA_CONFIG"
  sed -i 's/\r$//' "$KIBANA_CONFIG"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    key="${line%%: *}"
    value="${line#*: }"
    value=$(echo "$value" | tr -d ' \t\r\n')
    key_escaped=$(echo "$key" | sed 's/\./\\./g')
    if grep -qE "^#[[:space:]]*${key_escaped}:" "$KIBANA_CONFIG"; then
      sed -i.bak "s/^#[[:space:]]*${key_escaped}:.*/${key}: ${value}/" "$KIBANA_CONFIG"
      rm -f "${KIBANA_CONFIG}.bak"
    fi
  done < /tmp/keys-keep.txt
  echo "Re-seeded config from template"
else
  echo "Config already exists, preserving"
fi

# --- 1. Inject CA fingerprint + full certificate into Fleet output ---
if [ -n "${CA_CERT_PATH:-}" ] && [ -f "$CA_CERT_PATH" ]; then
  NODE_BIN=$(find /usr/share/kibana/node -name node -type f 2>/dev/null | head -1)
  FP=$("${NODE_BIN:-node}" -e "
    const crypto = require('crypto');
    const pem = require('fs').readFileSync('${CA_CERT_PATH}', 'utf8');
    const der = Buffer.from(pem.replace(/-----[^-]+-----/g, '').replace(/\s/g, ''), 'base64');
    console.log(crypto.createHash('sha256').update(der).digest('hex'));
  " 2>/dev/null) || true
  if [ -n "$FP" ]; then
    if grep -q "ca_trusted_fingerprint:" "$KIBANA_CONFIG"; then
      sed -i.bak "s|^.*ca_trusted_fingerprint:.*|    ca_trusted_fingerprint: ${FP}|" "$KIBANA_CONFIG"
      rm -f "${KIBANA_CONFIG}.bak"
      echo "Set ca_trusted_fingerprint: ${FP}"
    fi
  fi

  # Embed the full CA PEM so agents receive it through the policy
  # (elastic-endpoint needs the actual cert, not just the fingerprint)
  if grep -q "#ssl.certificate_authorities:" "$KIBANA_CONFIG"; then
    # Build the YAML block: ssl.certificate_authorities with a PEM literal
    {
      echo "    ssl:"
      echo "      certificate_authorities:"
      echo "        - |"
      while IFS= read -r line; do
        echo "          $line"
      done < "$CA_CERT_PATH"
    } > /tmp/ssl_block.txt

    awk '
      /#ssl\.certificate_authorities:/ { skip=1; while ((getline block < "/tmp/ssl_block.txt") > 0) print block; next }
      { print }
    ' "$KIBANA_CONFIG" > "${KIBANA_CONFIG}.tmp"
    mv "${KIBANA_CONFIG}.tmp" "$KIBANA_CONFIG"
    rm -f /tmp/ssl_block.txt
    echo "Embedded CA certificate in Fleet output"
  fi
fi

# --- 2. Replace internal Docker hostnames with the external host ---
# Only replaces in Fleet-specific sections (indented yaml list items),
# preserving elasticsearch.hosts used by Kibana itself.
host_port() {
  # ES_PORT/KIBANA_PORT/FLEET_PORT may be "5601" or "127.0.0.1:5601"
  local value="${1:-$2}"
  echo "${value##*:}"
}

if [ -n "${FLEET_EXTERNAL_HOST:-}" ]; then
  FLEET_P="$(host_port "${FLEET_PORT:-}" 8220)"
  ES_P="$(host_port "${ES_PORT:-}" 9200)"
  KIBANA_P="$(host_port "${KIBANA_PORT:-}" 5601)"
  FLEET_EXT="https://${FLEET_EXTERNAL_HOST}:${FLEET_P}"
  ES_EXT="https://${FLEET_EXTERNAL_HOST}:${ES_P}"
  PUBLIC_URL="https://${FLEET_EXTERNAL_HOST}:${KIBANA_P}"

  if ! grep -qF "$FLEET_EXT" "$KIBANA_CONFIG"; then
    sed -i.bak "s|^ *- https://fleet-server:8220|  - ${FLEET_EXT}|" "$KIBANA_CONFIG"
    rm -f "${KIBANA_CONFIG}.bak"
    echo "Fleet Server host → ${FLEET_EXT}"
  fi

  if ! grep -qF "$ES_EXT" "$KIBANA_CONFIG"; then
    sed -i.bak "s|^ \{4,\}- https://elasticsearch:9200|      - ${ES_EXT}|" "$KIBANA_CONFIG"
    rm -f "${KIBANA_CONFIG}.bak"
    echo "Elasticsearch output → ${ES_EXT}"
  fi

  if grep -qE "^server\.publicBaseUrl:" "$KIBANA_CONFIG"; then
    sed -i.bak "s|^server\.publicBaseUrl:.*|server.publicBaseUrl: ${PUBLIC_URL}|" "$KIBANA_CONFIG"
    rm -f "${KIBANA_CONFIG}.bak"
  else
    printf '\nserver.publicBaseUrl: %s\n' "$PUBLIC_URL" >> "$KIBANA_CONFIG"
  fi
  echo "Kibana publicBaseUrl → ${PUBLIC_URL}"
fi

# --- 3. Generate and inject encryption keys ---
needs_patch=false
for key in xpack.security.encryptionKey xpack.encryptedSavedObjects.encryptionKey xpack.reporting.encryptionKey; do
  key_escaped=$(echo "$key" | sed 's/\./\\./g')
  if grep -qE "^${key_escaped}:" "$KIBANA_CONFIG"; then
    continue
  fi
  needs_patch=true
  break
done

if [ "$needs_patch" = false ]; then
  echo "Kibana encryption keys already set, skipping."
  exit 0
fi

/usr/share/kibana/bin/kibana-encryption-keys generate -q > /tmp/keys.txt 2>/dev/null || true
if [ ! -s /tmp/keys.txt ]; then
  echo "Error: kibana-encryption-keys generate produced no output" >&2
  exit 1
fi

while IFS= read -r line; do
  [ -z "$line" ] && continue
  key="${line%%: *}"
  value="${line#*: }"
  value=$(echo "$value" | tr -d ' \t\r\n')
  key_escaped=$(echo "$key" | sed 's/\./\\./g')
  if grep -qE "^#[[:space:]]*${key_escaped}:" "$KIBANA_CONFIG"; then
    sed -i.bak "s/^#[[:space:]]*${key_escaped}:.*/${key}: ${value}/" "$KIBANA_CONFIG"
    rm -f "${KIBANA_CONFIG}.bak"
    echo "Set ${key}"
  fi
done < /tmp/keys.txt

echo "Done."
