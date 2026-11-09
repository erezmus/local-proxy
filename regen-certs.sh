#!/usr/bin/env bash
# Regenerate the local TLS certificate used by Traefik, or check its expiry with --check.
# Hostnames are read from hosts.txt (one per line, # for comments), which is created from
# hosts.example.txt on first run.
set -euo pipefail

cd "$(dirname "$0")"

if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ "$1" != "--check" ]; }; then
  echo "Usage: $0 [--check]" >&2
  exit 1
fi

command -v openssl >/dev/null || { echo "openssl not found" >&2; exit 1; }

check_cert() {
  local cert="certs/local-cert.pem"
  if [ ! -f "$cert" ]; then
    echo "Certificate not found: $cert; run ./regen-certs.sh to generate it" >&2
    return 1
  fi
  if ! openssl x509 -in "$cert" -noout -enddate; then
    echo "Could not read certificate: $cert" >&2
    return 1
  fi
  if ! openssl x509 -in "$cert" -noout -checkend 2592000 >/dev/null 2>&1; then
    echo "Warning: certificate expires in fewer than 30 days or has expired; run ./regen-certs.sh to renew it" >&2
  fi
}

if [ "${1:-}" = "--check" ]; then
  check_cert
  exit 0
fi

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

check_cert

if [ -n "$(docker compose ps -q traefik 2>/dev/null)" ]; then
  docker compose restart traefik
fi
