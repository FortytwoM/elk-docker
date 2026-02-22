#!/usr/bin/env bash

set -eu
set -o pipefail

# --- Prepare instances config ---
# Copy the read-only template to a writable location.
# If FLEET_EXTERNAL_HOST is set, inject it into elasticsearch and fleet-server entries.
cp tls/instances.yml /tmp/instances.yml

if [ -n "${FLEET_EXTERNAL_HOST:-}" ]; then
	echo "[+] Adding external host to certificates: ${FLEET_EXTERNAL_HOST}"

	# Determine whether the value looks like an IP address or a DNS name
	if echo "$FLEET_EXTERNAL_HOST" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
		FIELD="ip"
	else
		FIELD="dns"
	fi

	for name in elasticsearch fleet-server; do
		sed -i "/^- name: ${name}$/,/^- name:/{
			/^  ${FIELD}:$/a\\  - ${FLEET_EXTERNAL_HOST}
		}" /tmp/instances.yml
	done
fi

declare symbol=⠍

echo '[+] CA certificate and key'

if [ ! -f tls/certs/ca/ca.crt ] || [ ! -f tls/certs/ca/ca.key ]; then
	symbol=⠿

	rm -rf tls/certs/ca

	bin/elasticsearch-certutil ca \
		--silent \
		--pem \
		--out tls/certs/ca.zip

	unzip -o tls/certs/ca.zip -d tls/certs/ >/dev/null
	rm tls/certs/ca.zip

	echo '   ⠿ Created'
else
	echo '   ⠍ Already present, skipping'
fi

declare ca_fingerprint
ca_fingerprint="$(openssl x509 -fingerprint -sha256 -noout -in tls/certs/ca/ca.crt \
	| cut -d '=' -f2 \
	| tr -d ':' \
	| tr '[:upper:]' '[:lower:]'
)"

echo "   ${symbol} SHA256 fingerprint: ${ca_fingerprint}"

while IFS= read -r file; do
	echo "   ${symbol}   ${file}"
done < <(find tls/certs/ca -type f \( -name '*.crt' -or -name '*.key' \) -mindepth 1 -print)

symbol=⠍

echo '[+] Server certificates and keys'

if [ ! -f tls/certs/elasticsearch/elasticsearch.crt ] || [ ! -f tls/certs/elasticsearch/elasticsearch.key ]; then
	symbol=⠿

	rm -rf tls/certs/elasticsearch tls/certs/kibana tls/certs/fleet-server tls/certs/logstash

	bin/elasticsearch-certutil cert \
		--silent \
		--pem \
		--in /tmp/instances.yml \
		--ca-cert tls/certs/ca/ca.crt \
		--ca-key tls/certs/ca/ca.key \
		--out tls/certs/certs.zip

	unzip -o tls/certs/certs.zip -d tls/certs/ >/dev/null
	rm tls/certs/certs.zip

	find tls -name ca -prune -or -type f -name '*.crt' -exec sh -c 'cat tls/certs/ca/ca.crt >>"$1"' _ {} \;

	echo '   ⠿ Created'
else
	echo '   ⠍ Already present, skipping'
fi

while IFS= read -r file; do
	echo "   ${symbol}   ${file}"
done < <(find tls -name ca -prune -or -type f \( -name '*.crt' -or -name '*.key' \) -mindepth 1 -print)
