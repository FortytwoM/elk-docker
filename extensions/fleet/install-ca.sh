#!/bin/sh
set -eu

CA_SRC="${ELASTICSEARCH_CA:-/usr/share/elastic-agent/ca.crt}"

if [ -f "$CA_SRC" ]; then
  cp "$CA_SRC" /etc/pki/ca-trust/source/anchors/elk-ca.crt
  update-ca-trust
fi

STATE_DIR="/usr/share/elastic-agent/state"

# On first run, fleet.enc does not exist — let docker-entrypoint handle
# enrollment via elastic-agent container.
# On subsequent runs, fleet.enc exists in the persistent volume — bypass
# docker-entrypoint and start the agent directly from saved state.
# This prevents FLEET_SERVER_ENABLE from forcing a duplicate enrollment.
if [ -f "$STATE_DIR/fleet.enc" ] && [ -f "$STATE_DIR/container-paths.yml" ]; then
  echo "Fleet state found — starting directly from saved state (skipping enrollment)"
  umask 0007
  exec /usr/bin/tini -- elastic-agent run -e \
    --path.home=/usr/share/elastic-agent \
    --path.config="$STATE_DIR" \
    --path.logs="$STATE_DIR/data/logs"
fi

echo "No fleet state — running initial enrollment via docker-entrypoint"
exec /usr/bin/tini -- /usr/local/bin/docker-entrypoint "$@"
