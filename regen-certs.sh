#!/usr/bin/env bash
# Regenerate the local TLS certificate used by Traefik.
# Hostnames are read from hosts.txt (one per line, # for comments), which is created from
# hosts.example.txt on first run.
set -euo pipefail

cd "$(dirname "$0")"

command -v mkcert >/dev/null || { echo "mkcert not found" >&2; exit 1; }

if [ ! -f hosts.txt ]; then
  cp hosts.example.txt hosts.txt
  echo "Created hosts.txt from hosts.example.txt"
fi

hosts=()
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%%#*}"
  line="$(echo "$line" | xargs)"
  [ -n "$line" ] && hosts+=("$line")
done < hosts.txt

[ ${#hosts[@]} -gt 0 ] || { echo "no hostnames in hosts.txt" >&2; exit 1; }

mkdir -p certs
mkcert \
  -cert-file certs/local-cert.pem \
  -key-file certs/local-key.pem \
  "${hosts[@]}"
chmod 600 certs/local-key.pem

if [ -n "$(docker compose ps -q traefik 2>/dev/null)" ]; then
  docker compose restart traefik
fi
