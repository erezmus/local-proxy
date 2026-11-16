# local-proxy

A shared [Traefik](https://doc.traefik.io/traefik/) reverse proxy for local development. It terminates HTTPS with a locally trusted [mkcert](https://github.com/FiloSottile/mkcert) certificate and routes requests to containers on a shared Docker network (`local-proxy` by default).

## Files

| File                 | Purpose                                                                      |
| -------------------- | ---------------------------------------------------------------------------- |
| `docker-compose.yml` | Traefik, its static config (as flags), and the read-only Docker socket proxy |
| `.env.example`       | Settings you can override by copying to `.env` (git-ignored)                 |
| `dynamic.yml`        | Dynamic config: TLS certificates                                             |
| `hosts.example.txt`  | Default hostnames; copied to `hosts.txt` on first run                        |
| `hosts.txt`          | Hostnames the certificate covers, one per line (git-ignored)                 |
| `docs/setup.sh`      | Creates missing setup resources and starts the proxy                         |
| `regen-certs.sh`     | Regenerates `certs/` from `hosts.txt` and restarts Traefik                   |
| `certs/`             | Generated certificate and key (mounted read-only at `/certs`)                |

## Network name

The proxy network name comes from `PROXY_NETWORK` (default `local-proxy`). It sets both the network the container joins and the network Traefik uses to reach containers. To keep the default, skip to [Setup](#setup).

Every project routed through the proxy must use the same name, so the simplest option is to export it from your shell profile (`~/.zshrc` or `~/.bashrc`), then open a new terminal or `source` the file:

```sh
export PROXY_NETWORK=my-proxy
```

Compose prefers shell variables over values in `.env`, so the exported value applies to this project and every project that references `${PROXY_NETWORK}` (see [Routing a project through the proxy](#routing-a-project-through-the-proxy)). Alternatively, set it per project: copy `.env.example` to `.env` here, and set the same value in each project's own `.env`.

Compose only sees the variable when it's started from a shell that loaded your profile. Tools launched from a desktop launcher, such as an editor's built-in Docker integration, may not have it and will fall back to `local-proxy`. If that matters, set it in `~/.profile` as well, or in each project's `.env`.

Traefik's static config is passed as command-line flags in `docker-compose.yml` rather than a `traefik.yml`. Traefik doesn't substitute variables in its config file, and it ignores flags and environment variables once a config file is present.

## Setup

Prerequisites: Docker with the Compose plugin, `mkcert`, OpenSSL, and dnsmasq for `*.test` hostnames (see [DNS for `*.test`](#dns-for-test)).

From the repository root, run:

```sh
bash docs/setup.sh
```

The script uses Compose to resolve `PROXY_NETWORK` from the shell or `.env`, defaulting to `local-proxy`. It creates the network if needed, installs the mkcert CA and generates certificates if `certs/` is missing, then starts the proxy with `docker compose up -d`. It can be run again without recreating the network or certificates.

If `certs/` already exists, the script leaves it untouched and does not install the CA. Run `mkcert -install` separately if this machine still needs to trust the CA. If the directory is incomplete, run `./regen-certs.sh` to generate the certificate and key. To change hostnames or renew certificates, follow [Hostnames and certificates](#hostnames-and-certificates).

To change the network name later, set `PROXY_NETWORK` as above and rerun `bash docs/setup.sh`. Projects using the proxy must also be recreated so they join the new network.

## Automated checks

Install the following tools:

- **ShellCheck:** `brew install shellcheck` on macOS or `sudo apt install shellcheck` on Debian/Ubuntu. See the [ShellCheck installation guide](https://github.com/koalaman/shellcheck#installing) for other platforms.
- **Docker Compose plugin:** install [Docker Desktop](https://docs.docker.com/desktop/) or follow the [Compose plugin installation guide](https://docs.docker.com/compose/install/linux/) for Linux.
- **Gitleaks:** `brew install gitleaks` on macOS, or follow the [Gitleaks installation guide](https://github.com/gitleaks/gitleaks#installing). These commands require a version supporting the `git` subcommand.

From the repository root, run each check independently:

```sh
shellcheck regen-certs.sh docs/setup.sh
docker compose config --quiet
gitleaks git --redact --log-opts=--all
```

Each command exits non-zero on failure. Compose validates the configuration using the current environment and `.env`; it does not start containers. Gitleaks scans committed history reachable from local refs. To scan staged changes as well, run:

```sh
gitleaks git --pre-commit --redact
```

Confirm `.env` is untracked and ignored with `git check-ignore -v .env`; the command prints the applicable ignore rule and fails if the file is tracked or not ignored. Never commit local secrets.

To run these checks automatically before each commit, enable the included hook once per clone from the repository root:

```sh
git config core.hooksPath .githooks
```

This makes Git read hooks from the tracked `.githooks/` directory instead of `.git/hooks`, so any existing hook in `.git/hooks` stops running; move its commands into `.githooks/pre-commit` if you use one. The hook checks that `.env` is ignored, runs ShellCheck on `regen-certs.sh` and runs Compose, and scans staged changes with gitleaks, blocking the commit on failure. Run the ShellCheck command above separately for `docs/setup.sh`. ShellCheck and Compose inspect the working-tree files, so keep those files consistent with what you stage. Committed history is not scanned by the hook; run the full-history gitleaks command above manually; CI runs it on every push. Enable the hook separately in each clone.

### Continuous integration

`.github/workflows/ci.yml` runs on pushes to `main` and on pull requests. The static checks job runs ShellCheck on `regen-certs.sh`, `docker compose config`, the `.env` ignore check, and a full-history gitleaks scan. The smoke test job generates certificates with `regen-certs.sh`, starts the proxy, routes a `traefik/whoami` container through it, and checks that HTTPS works with the mkcert CA, HTTP redirects to HTTPS, the dashboard API lists the router, and the socket proxy rejects `POST` requests. The gitleaks and mkcert versions are pinned with checksums in the workflow's `env` block; update them by hand.

## Binding to a LAN address

By default the published ports (80 and 443) bind to `127.0.0.1`, so only this machine can reach the proxy. To reach it from another device, such as a NAS or a shared dev box, set the address to bind to in `.env` here:

```sh
PROXY_BIND=192.168.1.20   # this machine's LAN IP
```

Then rerun `docker compose up -d`. Compose reads `PROXY_BIND` from `.env` and uses it in the port mappings.

Before you do this:

- The dashboard has no authentication. Add basic auth first (see [Security](#security)).
- Other devices need DNS that points your `*.test` or other hostnames at `PROXY_BIND`. The dnsmasq setup in [DNS for `*.test`](#dns-for-test) only runs on this machine.
- Other devices need the mkcert root CA installed to trust the certificate.

## Synology NAS

To run the proxy on a Synology NAS, see [docs/synology.md](docs/synology.md). It covers port conflicts, certificates, and DNS on DSM.

## Routing a project through the proxy

Containers are **not** routed by default (`exposedByDefault: false`). For each service you want routed:

1. Add the `traefik.enable=true` label and a router rule.
2. Attach the service to the proxy network. Traefik can only reach containers on that network.

```yaml
services:
  api:
    # ...
    labels:
      - traefik.enable=true
      - traefik.http.routers.myapp-api.rule=Host(`myapp.localhost`)
      # only needed if the container exposes more than one port:
      - traefik.http.services.myapp-api.loadbalancer.server.port=8080
    networks:
      - default
      - proxy

networks:
  proxy:
    name: ${PROXY_NETWORK:-local-proxy}
    external: true
```

This is easiest in the project's `docker-compose.override.yml`, so the main compose file stays usable without the proxy.

Compose fills in `${PROXY_NETWORK}` from your shell environment first, then from the project's own `.env`. It never reads this repo's `.env`. If the variable isn't set anywhere, the `:-local-proxy` default applies, so projects work without any setup as long as you keep the default name. Run `docker compose config | grep -A1 '^  proxy:'` in a project to check which name it resolves to.

Router and service names must be unique across all projects that use the proxy.

HTTP on port 80 always redirects to HTTPS on port 443. Every route on 443 uses TLS with the certificate from `certs/`.

## Hostnames and certificates

The certificate covers the names listed in `hosts.txt`. That file is specific to your machine and git-ignored; the first run of `regen-certs.sh` creates it from `hosts.example.txt`. To add a hostname:

1. Add it to `hosts.txt`. Blank lines and `#` comments are ignored.
2. Run `./regen-certs.sh`. It overwrites `certs/` and restarts Traefik.

Names under `.localhost` resolve to `127.0.0.1` automatically on most systems. Names under `.test` need dnsmasq (see [DNS for `*.test`](#dns-for-test)). Any other domain needs an `/etc/hosts` entry or a similar dnsmasq rule.

Notes:

- Wildcards only cover one level: `*.localhost` matches `app.localhost` but not `api.app.localhost`.
- Some browsers reject `*.localhost`. If one does, list the exact hostname instead.
- Certificates expire after about 27 months. Rerun the script to renew.

To check the current certificate without regenerating it or restarting Traefik, run:

```sh
./regen-certs.sh --check
```

The script prints the expiry date and warns if fewer than 30 days remain or the certificate has expired. It also checks after regeneration. The warning does not change the exit status; missing or unreadable certificates cause an error. Checks are not automatic, so run the command periodically.

## DNS for `*.test`

dnsmasq answers every `*.test` lookup with `127.0.0.1`, so new hostnames work without editing `/etc/hosts`. Only `.test` queries go to dnsmasq; everything else uses your normal DNS.

### Linux (systemd-resolved)

For distros that use systemd-resolved (Ubuntu, Fedora, and others). Check with `resolvectl status`; if that command fails, your distro uses something else.

systemd-resolved already uses `127.0.0.53:53`, so dnsmasq listens on `127.0.0.2` instead, and systemd-resolved forwards only `.test` lookups to it.

```sh
sudo apt install dnsmasq     # Fedora: sudo dnf install dnsmasq; Arch: sudo pacman -S dnsmasq

sudo tee /etc/dnsmasq.d/local-wildcard.conf <<'EOF'
address=/test/127.0.0.1
listen-address=127.0.0.2
bind-interfaces
EOF

sudo mkdir -p /etc/systemd/resolved.conf.d
sudo tee /etc/systemd/resolved.conf.d/test.conf <<'EOF'
[Resolve]
DNS=127.0.0.2
Domains=~test
EOF

sudo systemctl enable dnsmasq
sudo systemctl restart dnsmasq systemd-resolved
```

On some distros `/etc/dnsmasq.d/` is not read by default. If `.test` names don't resolve, make sure `/etc/dnsmasq.conf` contains `conf-dir=/etc/dnsmasq.d/,*.conf`.

The install may report that dnsmasq failed to start. That's expected: until the config above exists, it tries to take port 53 from systemd-resolved. The restart at the end fixes it.

Check:

```sh
resolvectl query anything.test   # should return 127.0.0.1
```

### macOS (Homebrew)

macOS sends lookups for a domain to the nameserver named in `/etc/resolver/<domain>`.

```sh
brew install dnsmasq

cat >> "$(brew --prefix)/etc/dnsmasq.conf" <<'EOF'
address=/test/127.0.0.1
listen-address=127.0.0.1
EOF

sudo brew services start dnsq   # sudo: dnsmasq needs port 53

sudo mkdir -p /etc/resolver
echo "nameserver 127.0.0.1" | sudo tee /etc/resolver/test
```

Check:

```sh
scutil --dns | grep -A3 'domain   : test'          # the resolver should be listed
dscacheutil -q host -a name anything.test          # should return 127.0.0.1
```

`dig` and `nslookup` skip `/etc/resolver`, so they'll report `.test` names as not found even when everything works. Use the commands above instead.

## Security

This setup is for a single developer machine. Read these notes before changing the defaults.

- **Traefik reaches Docker only through a read-only socket proxy.** Full access to `/var/run/docker.sock` is effectively root on the host: the `:ro` flag on the mount does not limit what the Docker API allows, and `no-new-privileges` does not prevent a caller from starting a privileged container with the host filesystem mounted. So Traefik does not mount the socket. A [`tecnativa/docker-socket-proxy`](https://github.com/Tecnativa/docker-socket-proxy) container (`socket-proxy` in `docker-compose.yml`) mounts it instead and allows only the read endpoints Traefik's Docker provider needs: containers, networks, services, tasks, events, version, and ping. All `POST` and `DELETE` requests, including container creation, and every other endpoint, such as images, volumes, and exec, are rejected with `403`. The proxy listens only on an internal `socket-proxy` network shared with Traefik, not on the shared proxy network, so routed projects cannot reach it. The proxy container itself still has full socket access, so keep its configuration minimal. Members of the `docker` group already have full access regardless.
- **The Traefik container is locked down.** It runs as `PROXY_UID:PROXY_GID` (default `1000:1000`) instead of root, with a read-only root filesystem (only `/tmp` is a writable tmpfs), all Linux capabilities dropped except `NET_BIND_SERVICE`, and `no-new-privileges`. The UID must own `certs/local-key.pem`, which is mode `600`; if `id -u` is not `1000`, set `PROXY_UID` and `PROXY_GID` in `.env`, or Traefik logs `permission denied` for the key and serves its default self-signed certificate. If you add anything that writes to disk, such as ACME storage or file logs, mount a volume for it.
- **The dashboard has no authentication.** Anyone who can reach the proxy's ports with `Host: traefik.test` can read every router, service, and middleware. By default `PROXY_BIND` is `127.0.0.1`, so other machines on your network cannot reach the dashboard or any routed app. Setting `PROXY_BIND` to a LAN address exposes both to that network. Add [HTTP basic auth](https://doc.traefik.io/traefik/middlewares/http/basicauth/) to the dashboard router first, and do not expose the proxy on an untrusted network.
- **The mkcert root CA can sign for any name.** The root key is in the directory printed by `mkcert -CAROOT` (`rootCA-key.pem`). Anyone who has that file can make certificates your browser trusts for any site. Keep it private, and run `mkcert -uninstall` if you stop using this setup.
- **The leaf key is private to your user.** `regen-certs.sh` writes `certs/local-key.pem` with mode `600`. Do not copy it to other machines or commit it. It is git-ignored.
- **The Traefik and socket proxy images are pinned by digest** in `docker-compose.yml`. To upgrade, pick a new version, look up its digest, and update the line.

## Logs

```sh
docker compose logs -f traefik
```

Traefik logs at `INFO` level, and access logging (one line per request) is on. Both are set by the flags in `docker-compose.yml`.

## Dashboard

The dashboard is at <https://traefik.test/> on this machine only (see [Security](#security)). Traefik routes to its own dashboard: the labels on the `traefik` service point a router at the built-in `api@internal` service. The JSON API is under the same host, e.g. <https://traefik.test/api/http/routers>.

## License

This project is licensed under the GNU General Public License v3.0. See [`LICENSE.md`](LICENSE.md) for the full text.
