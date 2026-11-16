#!/usr/bin/env bash
# Set up the shared network, certificates, and proxy from the repository root.
set -euo pipefail

cd "$(dirname "$0")/.."

# Let Compose read .env and apply its own environment precedence and interpolation.
network="$(docker compose config --environment | sed -n 's/^PROXY_NETWORK=//p')"
network="${network:-local-proxy}"

if ! docker network inspect "$network" >/dev/null 2>&1; then
  docker network create "$network"
fi

if [ ! -d certs ]; then
  mkcert -install
  ./regen-certs.sh
elif [ ! -f certs/local-cert.pem ] || [ ! -f certs/local-key.pem ]; then
  echo "certs/ is incomplete; run ./regen-certs.sh to generate the certificate and key" >&2
  exit 1
fi

docker compose up -d
