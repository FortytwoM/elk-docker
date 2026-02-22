#!/bin/sh
set -eu

KIBANA_TEMPLATE="${KIBANA_TEMPLATE:-/kibana-template/kibana.yml}"
KIBANA_CONFIG="${KIBANA_CONFIG:-/kibana-config/kibana.yml}"

# On first run, seed the working config from the template.
# On subsequent runs, re-use the existing config to keep generated encryption keys.
if [ ! -f "$KIBANA_CONFIG" ]; then
  if [ ! -f "$KIBANA_TEMPLATE" ]; then
    echo "Error: template $KIBANA_TEMPLATE not found" >&2
    exit 1
  fi
  cp "$KIBANA_TEMPLATE" "$KIBANA_CONFIG"
  echo "Seeded config from template"
else
  echo "Config already exists, preserving"
fi

# --- 1. Inject CA fingerprint for Fleet output ---
if [ -n "${CA_CERT_PATH:-}" ] && [ -f "$CA_CERT_PATH" ]; then
  FP=$(openssl x509 -fingerprint -sha256 -noout -in "$CA_CERT_PATH" \
       | sed 's/.*=//' | tr -d ':' | tr '[:upper:]' '[:lower:]')
  if [ -n "$FP" ]; then
    if grep -q "ca_trusted_fingerprint:" "$KIBANA_CONFIG"; then
      sed -i.bak "s|^.*ca_trusted_fingerprint:.*|    ca_trusted_fingerprint: ${FP}|" "$KIBANA_CONFIG"
      rm -f "${KIBANA_CONFIG}.bak"
      echo "Set ca_trusted_fingerprint: ${FP}"
    fi
  fi
fi

# --- 2. Add external Fleet / ES URLs (external first so Kibana UI suggests it) ---
if [ -n "${FLEET_EXTERNAL_HOST:-}" ]; then
  FLEET_EXT="https://${FLEET_EXTERNAL_HOST}:8220"
  ES_EXT="https://${FLEET_EXTERNAL_HOST}:9200"

  if ! grep -qF "$FLEET_EXT" "$KIBANA_CONFIG"; then
    sed -i.bak "s|^ *- https://fleet-server:8220|  - ${FLEET_EXT}\n  - https://fleet-server:8220|" "$KIBANA_CONFIG"
    rm -f "${KIBANA_CONFIG}.bak"
    echo "Added Fleet Server host: ${FLEET_EXT} (primary)"
  fi

  if ! grep -qF "$ES_EXT" "$KIBANA_CONFIG"; then
    sed -i.bak "s|^ *- https://elasticsearch:9200|      - ${ES_EXT}\n      - https://elasticsearch:9200|" "$KIBANA_CONFIG"
    rm -f "${KIBANA_CONFIG}.bak"
    echo "Added Elasticsearch output: ${ES_EXT} (primary)"
  fi
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
