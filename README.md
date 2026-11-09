# local-proxy

A shared [Traefik](https://doc.traefik.io/traefik/) reverse proxy for local development. It terminates HTTPS with a locally trusted [mkcert](https://github.com/FiloSottile/mkcert) certificate and routes requests to containers on a shared Docker network (`local-proxy` by default).

## Automated Checks

To ensure code and configuration quality, we encourage running automated checks using pre-commit hooks or CI:

*   **Shellcheck:** Runs against `regen-certs.sh` to detect common scripting errors.
    `shellcheck regen-certs.sh`
*   **Compose Validation:** Ensures `docker-compose.yml` configuration is valid.
    `docker compose config --quiet`
*   **Gitleaks:** Scans the repository for accidental secret commits (tokens, API keys, etc.).
    `gitleaks detect --verbose`

## Files

| File                 | Purpose                                                                      |
| -------------------- | ---------------------------------------------------------------------------- |
| `docker-compose.yml` | The Traefik container and its static config (as command-line flags)          |
| `.env.example`       | Settings you can override by copying to `.env` (git-ignored)                 |
| `dynamic.yml`        | Dynamic config: TLS certificates                                             |
| `hosts.example.txt`  | Default hostnames; copied to `hosts.txt` on first run                        |
| `hosts.txt`          | Hostnames the certificate covers, one per line (git-ignored)                 |
| `regen-certs.sh`     | Regenerates `certs/` from `hosts.txt` and restarts Traefik                   |
| `certs/`             | Generated certificate and key (mounted read-only at `/certs`)                |

## Network name

The proxy network name comes from `PROXY_NETWORK` (default `local-proxy`). It sets both the network the container joins and the network Traefik uses to reach containers. To keep the default, skip to [Setup](#setup).

Every project routed through the proxy must use the same name, so the simplest option is to export it from your shell profile (`~/.zshrc` or `~/.bashrc`), then open a new terminal or `source` the file:

```sh
export PROXY_NETWORK=my-proxy
