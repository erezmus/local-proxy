# local-proxy

A shared [Traefik](https://doc.traefik.io/traefik/) reverse proxy for local development. It terminates HTTPS with a locally trusted [mkcert](https://github.com/FiloSottile/mkcert) certificate and routes requests to containers on a shared Docker network (`local-proxy` by default).

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
```

Compose prefers shell variables over values in `.env`, so the exported value applies to this project and every project that references `${PROXY_NETWORK}` (see [Routing a project through the proxy](#routing-a-project-through-the-proxy)). Alternatively, set it per project: copy `.env.example` to `.env` here, and set the same value in each project's own `.env`.

Compose only sees the variable when it's started from a shell that loaded your profile. Tools launched from a desktop launcher, such as an editor's built-in Docker integration, may not have it and will fall back to `local-proxy`. If that matters, set it in `~/.profile` as well, or in each project's `.env`.

Traefik's static config is passed as command-line flags in `docker-compose.yml` rather than a `traefik.yml`. Traefik doesn't substitute variables in its config file, and it ignores flags and environment variables once a config file is present.

## Setup

Prerequisites: Docker with the Compose plugin, `mkcert`, and dnsmasq for `*.test` hostnames (see [DNS for `*.test`](#dns-for-test)).

```sh
mkcert -install                                         # one-time: trust the mkcert CA in your system and browsers
docker network create "${PROXY_NETWORK:-local-proxy}"   # one-time: the shared network
./regen-certs.sh                                        # create hosts.txt from hosts.example.txt, then generate certs/
docker compose up -d
```

If you set `PROXY_NETWORK` only in `.env`, the shell can't see it, so type the name into `docker network create` yourself.

To change the network name later, set `PROXY_NETWORK` as above, create the new network, and rerun `docker compose up -d`. Projects using the proxy must also be recreated so they join the new network.

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
      - traefik.http.routers.myapp-api.rule=Host(`api.myapp.localhost`)
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

sudo brew services start dnsmasq   # sudo: dnsmasq needs port 53

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

- **Docker socket access is effectively root on the host.** Traefik reads container metadata through `/var/run/docker.sock`. The `:ro` flag on that mount does not limit what the Docker API allows. Anything that controls Traefik can start a privileged container with the host filesystem mounted, which gives root on the host. `no-new-privileges` does not prevent this. Members of the `docker` group already have the same access, so this only adds risk if Traefik itself is compromised or misconfigured. To reduce it, put a read-only socket proxy such as [`tecnativa/docker-socket-proxy`](https://github.com/Tecnativa/docker-socket-proxy) between Traefik and the socket, allowing only the container, network, service, and task endpoints. This repo does not do that yet.
- **The dashboard has no authentication.** Anyone on this machine who can reach `127.0.0.1:443` with `Host: traefik.test` can read every router, service, and middleware. The ports are bound to loopback, so other machines on your network cannot reach the dashboard or any routed app. If you change the bindings to expose the proxy to other machines, add a `basicauth` middleware to the dashboard router first.
- **The mkcert root CA can sign for any name.** The root key is in the directory printed by `mkcert -CAROOT` (`rootCA-key.pem`). Anyone who has that file can make certificates your browser trusts for any site. Keep it private, and run `mkcert -uninstall` if you stop using this setup.
- **The leaf key is private to your user.** `regen-certs.sh` writes `certs/local-key.pem` with mode `600`. Do not copy it to other machines or commit it. It is git-ignored.
- **The Traefik image is pinned by digest** in `docker-compose.yml`. To upgrade, pick a new version, look up its digest, and update the line.

## Logs

```sh
docker compose logs -f traefik
```

Traefik logs at `INFO` level, and access logging (one line per request) is on. Both are set by the flags in `docker-compose.yml`.

## Dashboard

The dashboard is at <https://traefik.test/> on this machine only (see [Security](#security)). Traefik routes to its own dashboard: the labels on the `traefik` service point a router at the built-in `api@internal` service. The JSON API is under the same host, e.g. <https://traefik.test/api/http/routers>.
