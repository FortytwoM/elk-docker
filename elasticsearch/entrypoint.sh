#!/bin/bash
set -e

if [ -n "${CRACK_JAR:-}" ] && [ -f "${CRACK_JAR}" ] && [ -n "${ELASTIC_VERSION:-}" ]; then
  echo "Applying x-pack-core patch from ${CRACK_JAR}"
  cp "${CRACK_JAR}" "/usr/share/elasticsearch/modules/x-pack-core/x-pack-core-${ELASTIC_VERSION}.jar"
fi

# Find and exec the official entrypoint (location varies across image versions)
for ep in /usr/local/bin/docker-entrypoint.sh /usr/share/elasticsearch/bin/docker-entrypoint.sh; do
  if [ -x "$ep" ]; then
    exec /bin/tini -- "$ep" "$@"
  fi
done

exec /bin/tini -- /usr/share/elasticsearch/bin/elasticsearch "$@"
