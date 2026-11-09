# Automated checks

The optional pre-commit hook checks staged changes with ShellCheck, Docker
Compose, and Gitleaks. Install those tools first: `shellcheck`, Docker with
the Compose plugin, and Gitleaks v8 with the `git` command.

From the repository root, install the hook:

```sh
hook=$(git rev-parse --git-path hooks/pre-commit)
mkdir -p "$(dirname "$hook")"
cp docs/pre-commit "$hook"
chmod +x "$hook"
```

This replaces any existing pre-commit hook at that path. If you already use
one, combine the checks instead. Install the hook in each clone; Git does not
automatically install hooks.

On every commit, the hook runs ShellCheck and Compose validation against
staged copies of `regen-certs.sh` and `docker-compose.yml`, then scans the
staged diff for secrets with Gitleaks. A missing tool or a failed check blocks
the commit. Compose validation does not start containers or require a running
Docker daemon. It uses the shell environment and defaults, not the local
`.env` file.

To scan existing Git history as well, run:

```sh
gitleaks git --redact
```

If a secret is found, remove it from the staged changes and rotate it as
appropriate. The hook only scans the staged diff; it does not retroactively
clean secrets from history.
