# FamilyApp deployment

Production origin: `https://famly-app.duckdns.org:8443`.
Port 443 belongs to the host's VPN. FamilyApp uses the existing Caddy ingress,
an isolated `familyapp-ingress` network, and `/opt/familyapp`. No application
container publishes a host port. SQLite lives in the `familyapp_data` volume.

## First installation

Install `compose.prod.yaml` in `/opt/familyapp`, the deployment script as
`/usr/local/sbin/familyapp-deploy`, and the forced SSH command as
`/usr/local/sbin/familyapp-ssh-command`; all must be root-owned and not writable
by the CI user. Validate the sudoers file with `visudo -cf` before installing it.
Use a separate `familyapp-deploy` account with an authorized key prefixed by
`restrict,command="/usr/local/sbin/familyapp-ssh-command"`. Do not give it Docker
group membership or access to other applications.

Create `familyapp-ingress` and attach shared Caddy to it. Record the network in
the actual Compose file used to create Caddy, so its next recreation preserves
the connection. Back up and validate the shared Caddy configuration before
adding `deploy/Caddyfile.familyapp`, then reload Caddy. The shared ingress
configuration requires the project owner's approval.

GitHub Actions repository secrets:

- `VPS_HOST`: server IP.
- `VPS_USER`: `familyapp-deploy`.
- `VPS_SSH_PRIVATE_KEY`: the dedicated CI private key.
- `VPS_SSH_KNOWN_HOSTS`: host key verified through the initial SSH connection.

Never use the root administration key for CI.

## Releases

The owner commits and pushes the source and workflow. Publish a GitHub Release
with a version tag such as `v0.1.0` targeting that commit. `release.yml` runs
backend tests, Flutter analysis and tests, builds the web client and Docker
images, pushes to GHCR, and deploys the exact image digests. A manual workflow
run can retry an existing version tag. The server does not build release images.

This workflow deploys the web app and backend; Android APK publication and
release signing are not configured yet.

The first release creates an empty database. Before subsequent releases the
deployment uses SQLite's backup API to save a consistent snapshot under
`/opt/familyapp/backups` with root-only access. Images from earlier releases are
not automatically removed. Monitor disk usage and retain backups deliberately.

## Initial parent accounts

After the first deployment, run on the server in an interactive terminal:

```bash
cd /opt/familyapp
docker compose --env-file .release.env -f compose.prod.yaml exec backend \
  flask --app familyapp bootstrap-parents
```

Enter and confirm a password of at least 12 characters for each account.
Passwords are hidden, stored as hashes, and never passed as command arguments.
This creates `vlad` (Влад) and `katya` (Катя) as equal parents of one family.
The command refuses to overwrite either existing account and commits both
accounts together. It does not create any children.

## Verification and recovery

The deploy script checks container health, public `/health`, HTTP 401 from
`/api/me`, and Flutter's bootstrap script at the public origin. The deployment
fails if any check fails; it does not automatically roll back schema changes.

The previous image digests are saved in `.release.env.previous`. To return to
those images after assessing schema compatibility:

```bash
cd /opt/familyapp
docker compose --env-file .release.env.previous -f compose.prod.yaml up -d --no-build --wait
```

Restoring a database backup is a separate destructive operation and requires
explicit approval. Preserve the current database before any restore.
