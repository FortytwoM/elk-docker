#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${1:-}" ]]; then
  echo "Usage: bash $0 <version>"
  echo "Example: bash $0 9.3.0"
  echo "Version should match ELASTIC_VERSION in the repo root .env file."
  exit 1
fi

VERSION="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

docker build --no-cache -f "${SCRIPT_DIR}/Dockerfile" \
  --build-arg VERSION="${VERSION}" \
  -t "elastic-xpack-crack:${VERSION}" "${SCRIPT_DIR}"

mkdir -p "${SCRIPT_DIR}/output"

docker run --rm \
  -v "${SCRIPT_DIR}/output:/crack/output" \
  "elastic-xpack-crack:${VERSION}"

echo
echo "Cracked jar: ${SCRIPT_DIR}/output/x-pack-core-${VERSION}.crack.jar"
echo "To use with elk-docker: uncomment the CRACK_JAR volume and env in docker-compose.yml, then restart elasticsearch."
