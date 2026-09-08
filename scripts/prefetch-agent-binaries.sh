#!/bin/sh
# Warm the local artifact cache so LAN agents never hit artifacts.elastic.co.
# Requires endpoint-artifacts to be up. Docker host needs outbound HTTPS once.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"

version="${ELASTIC_VERSION:-}"
if [ -z "$version" ] && [ -f .env ]; then
  version=$(grep -E '^ELASTIC_VERSION=' .env | tail -1 | cut -d= -f2- | tr -d '\r')
fi
version="${version:-9.5.3}"

files="
beats/elastic-agent/elastic-agent-${version}-windows-x86_64.zip
beats/elastic-agent/elastic-agent-${version}-linux-x86_64.tar.gz
beats/elastic-agent/elastic-agent-${version}-linux-arm64.tar.gz
endpoint-dev/endpoint-security-${version}-windows-x86_64.zip
endpoint-dev/endpoint-security-${version}-linux-x86_64.tar.gz
"

echo "Prefetching Elastic Agent ${version} binaries into endpoint-artifacts cache…"

for rel in $files; do
  [ -z "$rel" ] && continue
  for suffix in "" ".sha512" ".asc"; do
    path="/downloads/${rel}${suffix}"
    echo "  $path"
    docker compose exec -T endpoint-artifacts wget -q -O /dev/null "http://127.0.0.1${path}" || {
      echo "  skip (not found): $path" >&2
    }
  done
done

echo "GPG key…"
docker compose exec -T endpoint-artifacts wget -q -O /dev/null http://127.0.0.1/GPG-KEY-elastic-agent || true
echo "Done. Agents should use http://<FLEET_EXTERNAL_HOST>:9080/downloads/"
