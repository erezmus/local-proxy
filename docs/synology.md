# Running local-proxy on Synology

This guide covers running the proxy on a Synology NAS with DSM Container Manager, and reaching it from other devices on your network. It assumes you have read the main [README](../README.md), especially [Binding to a LAN address](../README.md#binding-to-a-lan-address) and [Security](../README.md#security).

> **Status: unverified.** These steps were written from the repo's setup and Synology's documented behaviour. They have not yet been run end to end on a real NAS. Steps marked **(check)** need confirming on your DSM version.

## Differences from the Linux and macOS setup

| Area | Linux / macOS | Synology |
| --- | --- | --- |
| Ports 80 and 443 | Free on a workstation | Often used by DSM, Web Station, or the reverse proxy. See [Port conflicts](#port-conflicts). |
| `PROXY_NETWORK` | Set in a shell profile | Set in the project's `.env`. The NAS has no login shell profile for Container Manager. |
| Certificates | `mkcert` on this machine | `mkcert` isn't available on DSM. Generate certificates on a workstation and copy them over. See [Certificates](#certificates). |
| DNS for `*.test` | dnsmasq on this machine | DSM has no dnsmasq. Use a network DNS server or hosts-file entries on each client. See [DNS](#dns). |
| Client trust | `mkcert -install` here | Each client device must trust the mkcert root CA. |
| `regen-certs.sh` | Runs on the host | Needs the `docker compose` CLI on the host. Run it on a workstation, not the NAS (see [Certificates](#certificates)). |

## 1. Prepare DSM

1. Install **Container Manager** from Package Center.
2. Check which services are listening on ports 80 and 443 (see [Port conflicts](#port-conflicts)).
3. Note the NAS's LAN IP address. You will use it as `PROXY_BIND`. Reserve it in your router's DHCP settings so it doesn't change.

## Port conflicts

The proxy publishes ports 80 and 443 on `PROXY_BIND`. If DSM, Web Station, or the reverse proxy already uses them, Docker will fail to start the Traefik container with a "port is already allocated" error.

To see what is listening, connect over SSH and run:

```sh
sudo ss -tlnp | grep -E ':(80|443)\s'
```

Either move the other service off ports 80 and 443 in its own settings **(check: exact menu locations vary by DSM version)**, or pick different host ports for this proxy. Changing the host ports means editing the `ports:` entries in `docker-compose.yml`, which this repo does not parameterise. Moving the other service is usually simpler.

## 2. Create the shared network

Traefik and every routed project must share the `local-proxy` network (or whatever `PROXY_NETWORK` you choose). Create it once, either:

- in Container Manager under **Network**, with the driver set to `bridge`, or
- over SSH:

  ```sh
  sudo docker network create local-proxy
  ```

## 3. Configure the project

Copy this repo to a shared folder on the NAS (for example `/volume1/docker/local-proxy`). Then create `.env` in that folder:

```sh
PROXY_NETWORK=local-proxy
PROXY_BIND=192.168.1.20   # replace with your NAS's LAN IP
```

Container Manager reads `.env` from the project folder. Because the NAS has no shell profile, this file is the only place to set these values here.

Do not put `certs/` in a folder that other users can read. It holds the private key (see [Security](../README.md#security)).

## 4. Certificates

`mkcert` is not available on DSM, so generate the certificates on a workstation:

1. On the workstation, follow the README to install `mkcert` and run `mkcert -install`.
2. Copy `hosts.example.txt` to `hosts.txt` and list the hostnames you need.
3. Run `./regen-certs.sh`. It writes `certs/`.
4. Copy the `certs/` folder to `/volume1/docker/local-proxy/certs/` on the NAS.
5. Copy the mkcert root CA to any client that needs to trust it. The root CA file is `rootCA.pem` in the directory printed by `mkcert -CAROOT`. Do not copy `rootCA-key.pem` to the NAS.

When you renew or add hostnames, repeat steps 1 to 4 and restart the project. `regen-certs.sh` also restarts Traefik on the workstation, so on the NAS restart the project from Container Manager.

## 5. Start the proxy

In Container Manager, go to **Project**, click **Create**, and select the `local-proxy` folder. Container Manager reads `docker-compose.yml` and `.env`. Start the project.

Check that Traefik is running and listening on the NAS's LAN IP:

```sh
sudo docker ps --filter name=traefik
sudo ss -tlnp | grep -E ':(80|443)\s'
```

The listening address should be `192.168.1.20` (your `PROXY_BIND`), not `127.0.0.1`.

## DNS

Other devices need `*.test` hostnames to resolve to `PROXY_BIND`. DSM has no dnsmasq, so pick one of:

- **Network DNS.** Add wildcard records for `*.test` pointing at `PROXY_BIND` on your router or DNS server (for example Pi-hole or AdGuard Home, if you run one).
- **Hosts file.** On each client, add an entry for every hostname in `hosts.txt`:

  ```text
  192.168.1.20   traefik.test api.myapp.test
  ```

Hosts-file entries must be updated whenever you add a hostname.

## Routing a project

Projects on the NAS follow the same steps as in the README, [Routing a project through the proxy](../README.md#routing-a-project-through-the-proxy). Attach each service to the `local-proxy` network, and set `PROXY_NETWORK` in that project's `.env` so it matches.

## Verify from another device

From a client on the same network:

1. Confirm the hostname resolves: `ping -c1 api.myapp.test` should show `192.168.1.20`.
2. Open `https://api.myapp.test/` in a browser that trusts the mkcert root CA. The certificate should be valid with no warnings.
3. Confirm HTTP redirects to HTTPS: `curl -sI http://api.myapp.test/` should return a `301` or `308` pointing to `https://`.

If the page doesn't load, check the NAS firewall under **Control Panel > Security > Firewall** **(check)**, then the Traefik logs in Container Manager.

## Security reminder

The dashboard has no authentication. Once `PROXY_BIND` is a LAN address, anyone on your network can read every router, service, and middleware. Add basic auth to the dashboard router before you do this (see [Security](../README.md#security)).
