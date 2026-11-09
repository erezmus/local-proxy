# Running local-proxy on Synology

This guide sets up the proxy on a Synology NAS and reaches a test container
from another device on the LAN. It uses DSM Container Manager and SSH for
network creation and diagnostics.

> **Status: unverified.** This walkthrough has not been tested end to end on
> a real NAS. Container Manager screens and available commands can vary by DSM
> version.

Read the README's [Security](../README.md#security) section first. This setup
exposes the proxy to your LAN, not just the NAS itself. Do not forward its ports
from the internet.

## 1. Prepare the NAS

1. Install **Container Manager** from Package Center.
2. Give the NAS a stable LAN address, for example by reserving its DHCP lease.
   This guide uses `192.168.1.20`; replace it with your NAS's address.
3. Enable SSH in DSM and connect with an account that can use `sudo`. Keep
   access to DSM available while changing network or port settings.
4. Copy this repository into a NAS folder accessible to Container Manager,
   for example `/volume1/docker/local-proxy`. The folder must contain
   `docker-compose.yml`, `dynamic.yml`, and the other repository files.

### Check ports 80 and 443

DSM, Web Station, DSM's reverse proxy, or another container may already use
these ports. The proxy needs both ports on the NAS's LAN address. A service
listening on all addresses can conflict even if the proxy binds to one address.

Over SSH, inspect listeners and published container ports:

```sh
sudo netstat -tlnp | grep -E ':(80|443)([[:space:]]|$)'
sudo docker ps --format 'table {{.Names}}\t{{.Ports}}'
```

If `netstat` is unavailable, try
`sudo ss -tlnp | grep -E ':(80|443)([[:space:]]|$)'`. Listener details may
depend on DSM version. Check DSM, Web Station, and reverse-proxy settings as
well as other containers. Move or disable conflicting services only if it is
safe to do so; do not lock yourself out of DSM. If the ports cannot be freed,
this walkthrough cannot use its normal URLs. Alternative host ports require
changes to the Compose port mappings and HTTP redirect configuration.

If DSM's firewall is enabled, allow TCP ports 80 and 443 from the client network.

## 2. Create the network and configure the proxy

Create the shared bridge network once on the NAS:

```sh
sudo docker network create local-proxy
```

If it already exists, check it with `sudo docker network inspect local-proxy`
instead. Every routed project must use this same external network.

Create `.env` in `/volume1/docker/local-proxy`:

```dotenv
PROXY_NETWORK=local-proxy
PROXY_BIND=192.168.1.20
```

Use the actual NAS LAN address. Container Manager does not load your
interactive shell profile, so put these values in the project's `.env`.
A different network name must also be created and configured in every routed
project's own `.env`.

The dashboard has no authentication. Before exposing the proxy to the LAN,
disable its router in the NAS copy of `docker-compose.yml`: remove the
`labels:` block under the `traefik` service containing the three
`traefik.enable` and `traefik.http.routers.dashboard.*` labels. This leaves
the dashboard inaccessible through the proxy. Alternatively, configure
[Traefik basic auth](https://doc.traefik.io/traefik/middlewares/http/basicauth/)
before starting it.

## 3. Generate and copy certificates

Generate the certificate on a trusted workstation, not DSM. Install
[mkcert](https://github.com/FiloSottile/mkcert#installation) there, then run:

```sh
mkcert -install
mkdir -p certs
umask 077
mkcert -cert-file certs/local-cert.pem -key-file certs/local-key.pem \
  whoami.test
```

Include every hostname you intend to use in the `mkcert` command. A wildcard
such as `*.test` covers one level only. For future renewals, keep a list of
the names, for example in `hosts.txt` on the workstation.

On the NAS, create the destination directory within the project folder and
restrict access to it. For example, over SSH:

```sh
mkdir -p /volume1/docker/local-proxy/certs
chmod 700 /volume1/docker/local-proxy/certs
```

From the workstation, securely copy the two generated files to that directory,
using an SSH account with write access:

```sh
scp certs/local-cert.pem certs/local-key.pem \
  USER@192.168.1.20:/volume1/docker/local-proxy/certs/
```

Replace `USER` and the address as needed. On the NAS, restrict the private key:

```sh
chmod 600 /volume1/docker/local-proxy/certs/local-key.pem
```

Ensure the container can read both files and that NAS users who do not need
the key cannot read the directory. The leaf key must be copied to the NAS for
Traefik to serve HTTPS; do not commit it or distribute it to clients.

`regen-certs.sh` uses the host's `docker compose` CLI to check and restart
Traefik. The manual `mkcert` command above avoids requiring that CLI on DSM
or restarting an unrelated workstation project. When adding names or renewing,
generate and copy both files again, then restart the proxy project in Container
Manager.

### Trust the CA on clients

The workstation's public root certificate is `rootCA.pem` in the directory
printed by `mkcert -CAROOT`. Transfer **only that file** to each client over
a trusted channel, then install it as a trusted root CA:

- **Windows:** run `certutil -user -addstore Root rootCA.pem`.
- **macOS:** run `sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain rootCA.pem`.
- **Debian/Ubuntu:** copy it to
  `/usr/local/share/ca-certificates/local-proxy-mkcert.crt` and run
  `sudo update-ca-certificates`.

Other systems and browsers may use separate trust stores; import the
certificate into those stores as needed. The workstation running
`mkcert -install` is already configured by mkcert.

Never copy `rootCA-key.pem` to the NAS or clients. Anyone with that key can
issue certificates trusted by those clients.

## 4. Start the proxy

In Container Manager, create a project using the existing
`/volume1/docker/local-proxy` folder and its `docker-compose.yml`, then build
or start the project. Container Manager should read the `.env` in that project
folder. Check the project configuration or logs if it does not: the network
must resolve to `local-proxy` and the published ports must bind to the NAS LAN
address, not `127.0.0.1`.

Over SSH, check the container and its published ports:

```sh
sudo docker ps --filter name=traefik --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
```

If startup reports that a port is allocated, revisit the port-conflict check.
If Traefik reports certificate errors, check the filenames, mount path, and
permissions. Container Manager's project logs are also useful.

## 5. Start a test service

Create a separate folder on the NAS, for example
`/volume1/docker/proxy-test`, with this `docker-compose.yml`:

```yaml
services:
  whoami:
    image: traefik/whoami:v1.10
    labels:
      - traefik.enable=true
      - traefik.http.routers.synology-test.rule=Host(`whoami.test`)
      - traefik.http.services.synology-test.loadbalancer.server.port=80
    networks:
      - proxy

networks:
  proxy:
    name: ${PROXY_NETWORK:-local-proxy}
    external: true
```

Create `.env` in that folder with `PROXY_NETWORK=local-proxy`, then create and
start a second Container Manager project from the folder. It joins the existing
network; it does not publish its own ports.

For other projects, use unique router and service names and follow
[Routing a project through the proxy](../README.md#routing-a-project-through-the-proxy).
Each project has its own `.env`; it does not inherit the proxy's file.

## 6. Configure client DNS

Clients must resolve the test hostname to the NAS, not to their own loopback
address. Use either:

- A network DNS server configured to resolve `whoami.test` or `*.test` to
  `192.168.1.20`, with clients configured to use that server; or
- An entry in each client's hosts file:

  ```text
  192.168.1.20  whoami.test
  ```

On Linux and macOS the hosts file is `/etc/hosts`; on Windows it is
`C:\Windows\System32\drivers\etc\hosts` and must be edited as administrator.
Hosts files do not support wildcards, so add each hostname separately. DSM
does not provide the workstation dnsmasq setup described in the README.

## 7. Verify from another device

From a client on the same network, after installing the CA:

1. Check that `whoami.test` resolves to the NAS address, for example with
   `ping whoami.test`. A blocked ping response does not necessarily mean DNS
   failed; check the address printed by the command.
2. Open <https://whoami.test/>. The test service should respond without a
   certificate warning.
3. Run `curl -I http://whoami.test/`. It should return a redirect to
   `https://whoami.test/`.

If DNS fails, check the client's DNS server or hosts file. If the connection
fails, check the NAS firewall, port conflicts, and Container Manager logs. A
certificate warning usually means the client does not trust the CA, the
certificate does not cover the hostname, or Traefik cannot read the copied
files. A Traefik 404 suggests the test container, router label, or shared
network needs checking.
