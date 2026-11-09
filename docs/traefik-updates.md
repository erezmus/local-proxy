# Automated Traefik updates

Renovate can monitor the pinned Traefik image in `docker-compose.yml` and
open pull requests when the digest for its tag changes. It can also propose
tag upgrades with the corresponding digest. Updates are not automatically
merged; review and test them before merging.

## Enable Renovate

The configuration lives in `renovate.json` at the repository root, where
Renovate discovers it automatically. It enables only the Docker Compose
manager.

A repository administrator must enable Renovate for this repository:

- **Hosted Renovate app:** install the app and enable it for this
  repository. Because `renovate.json` already exists, no onboarding
  configuration is needed.
- **Self-hosted Renovate:** include this repository in the runner's
  configured repositories. Configure the runner's platform, credentials,
  and schedule separately.

Without an enabled app or scheduled runner, the configuration alone does
not open pull requests. See the
[Renovate documentation](https://docs.renovatebot.com/) for installation and
runner setup.

## Review an update

Check that the PR retains a `traefik:<tag>@sha256:<digest>` image reference
and review the upstream release notes, especially for tag upgrades. On a
machine with Docker Compose and the proxy prerequisites configured, validate
and try the proposed image:

```sh
docker compose config --quiet
docker compose pull traefik
docker compose up -d
docker compose ps
docker compose logs traefik
```

Confirm that the container becomes healthy and that HTTPS routing still
works. A digest pin makes the image reproducible, but does not by itself
establish that an upstream image is safe.
