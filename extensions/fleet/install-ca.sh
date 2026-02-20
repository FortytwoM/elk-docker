#!/bin/sh
set -eu

CA_SRC="${ELASTICSEARCH_CA:-/usr/share/elastic-agent/ca.crt}"

if [ -f "$CA_SRC" ]; then
  cp "$CA_SRC" /etc/pki/ca-trust/source/anchors/elk-ca.crt
  update-ca-trust
fi

exec /usr/bin/tini -- /usr/local/bin/docker-entrypoint "$@"
