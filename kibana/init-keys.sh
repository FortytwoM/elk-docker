#!/bin/sh
# Generates Kibana encryption keys and injects CA fingerprint for Fleet.
# Idempotent: only patches lines that are still commented out.
set -eu

KIBANA_CONFIG="${KIBANA_CONFIG:-/kibana-config/kibana.yml}"

if [ ! -f "$KIBANA_CONFIG" ]; then
  echo "Error: $KIBANA_CONFIG not found" >&2
  exit 1
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

# --- 2. Generate and inject encryption keys ---
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
