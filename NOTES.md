# Operator notes

Pre-deploy checklist, open questions, and one-shot decisions that don't belong in code comments.

> **IdP is Zitadel, not kanidm.** kanidm lacked the OAuth2 device authorization grant
> (RFC 8628) NetBird needs for headless / SSH enrollment. The IdP host (`id.<domain>`) now runs
> Zitadel (NixOS `services.zitadel`, zitadel 2.71.7) backed by local Postgres. NetBird's OIDC
> apps are no longer provisioned on-box — they're created by the `tofu/zitadel` phase. See the
> phased run order below.

## Before first apply
- Replace placeholders in `nix/_config.nix` (`domain`, `zitadelHost`, `netbirdHost`, `cloudflareZone`, `adminEmail`).
- Replace placeholder age recipients in `.sops.yaml` (both `admin_luuk` and `host_netbird`). Generate the admin key with `age-keygen`; the host key is derived from the host's freshly generated `ssh_host_ed25519_key.pub` via `ssh-to-age` (do this after the very first apply, then re-encrypt and re-apply, or pre-generate an age keypair and write the private key into `secrets/host-age-key.txt` so tofu can inject it).
- `secrets/secrets.yaml` must carry (sops-encrypted): `zitadel/masterkey` (**exactly 32 bytes** — `openssl rand -hex 16`), `zitadel/admin-password` (FirstInstance human; meet Zitadel's complexity policy), `zitadel/smtp-password`, plus the existing `acme/*` and `netbird/*` values.
- Object-storage state bucket (Hetzner `*.your-objectstorage.com`, versioning ON) + access key; one bucket, three state keys (`host/`, `zitadel/`, `netbird-account/`). `use_lockfile = true` works on Hetzner Object Storage (conditional writes supported).
- Two Cloudflare tokens, both `Zone:DNS:Edit` on the apex zone — one for tofu CI, one in sops as `acme/cloudflare-token-env` for ACME DNS-01.
- Hetzner Cloud API token as `TF_VAR_hcloud_token` / Actions secret.

## Phased run order (no manual steps between phases)
```sh
cd tofu/host          && tofu apply   # server + DNS + nixos-anywhere; Zitadel + Postgres come up
cd ../zitadel         && tofu apply   # reads the FirstInstance PAT over SSH, provisions the NetBird
                                      # project/apps/idp-user/roles, delivers the generated client
                                      # ids/secret to /var/lib/netbird-oidc, restarts netbird
cd ../netbird-account && tofu apply   # NetBird account content (groups, policy, setup key, DNS)
```
`tofu/zitadel` authenticates as the FirstInstance machine user by SSH-reading
`/var/lib/zitadel/bootstrap-pat` from the box (key auth via your ssh-agent — the same key that
ran the host deploy). DNS points `id.<domain>` at the box, so it doubles as the SSH target.

On a fresh box, `netbird-management` and `netbird-dashboard-render` hold (ConditionPathExists)
until `tofu/zitadel` delivers the ids; its `systemctl restart` then starts them. So phase 1 not
being immediately green for NetBird is expected — it converges after phase 2, unattended.

## §10.2 — NetBird management API reachability
Verify from a hosted GitHub runner that `https://netbird.<domain>` is reachable BEFORE relying on the `netbird-account` module. Quick check: any successful `curl -fsS https://netbird.<domain>/api/users -H "Authorization: Token ..."` from a GH-hosted runner after first apply.

## Zitadel bootstrap credential
`FirstInstance` (in `nix/zitadel/default.nix`, processed once and tracked in Postgres) creates
the org `infra`, the admin human (`luuk`), and one IAM_OWNER machine user `tier0-bootstrap`
whose PAT is written to `/var/lib/zitadel/bootstrap-pat`. That PAT is the chicken-and-egg
credential `tofu/zitadel` uses; it cannot be created by the thing that consumes it, so the host
mints it. On a nuke + re-apply the DB is fresh, FirstInstance reruns, a new PAT is written —
`tofu/zitadel` re-reads it live, so nothing manual is needed. Console login: the admin human at
`https://id.<domain>` (loginname `luuk@infra.<id-domain>`; password from sops).

## NetBird ↔ Zitadel (settled in research, recorded so it isn't re-derived)
- `IdpManagerConfig.ManagerType = "zitadel"` (login + user sync). The idp-mgmt service user uses
  `client_credentials` and holds `ORG_USER_MANAGER`. **Enabling the IdP manager removes the old
  kanidm-era `tofu import netbird_user.luuk` dance** (the "idp manager must be enabled to send
  user invites" error is gone). Trade-off: **NetBird now writes Zitadel users** — see ownership
  note below.
- Device flow: `DeviceAuthorizationFlow.Provider = "hosted"` (RFC 8628 device/token endpoints
  auto-discovered). This is the whole reason for the migration — headless / SSH peers enroll
  without a setup key.
- Two OIDC apps (both public/PKCE, no secret): `netbird-dashboard` (USER_AGENT) and `netbird-cli`
  (NATIVE + `OIDC_GRANT_TYPE_DEVICE_CODE`). Created in `tofu/zitadel`.
- Zitadel uses **roles, not groups**: a `zitadel_action` flattens project roles into a flat
  `groups` claim that NetBird's JWT group-sync reads.

## First-deploy verification items (version-sensitive — tune against zitadel 2.71.7)
- **Zitadel ↔ Postgres**: peer auth over the unix socket with a single owner role (`zitadel`)
  acting as both User and Admin. Most likely first-boot failure point; if `zitadel setup` can't
  create/connect, grant the role extra attributes or check `Database.postgres.Admin`.
- **`tofu/zitadel` enums/resources**: validated against provider `zitadel/zitadel` 2.12.8, but
  confirm the live API accepts the device-code grant, the `ORG_USER_MANAGER` grant, and the
  roles→`groups` action + trigger on a real plan/apply.
- **Token audience**: `HttpConfig.AuthAudience` is the **NetBird project id** (delivered to
  `/var/lib/netbird-oidc/audience`), not a per-app client id. Zitadel includes the project id in
  every token's `aud` ("by default all client id's and the project id are included"), so this one
  value validates both browser (dashboard app) and device-flow (cli app) tokens — a per-app
  client id would only match one flow. Confirm a real device-code token's `aud` actually carries
  the project id on first deploy.
- **SMTP**: protonmail submission is `smtp.protonmail.ch:587` STARTTLS (`TLS: true`). Confirm a
  Zitadel password-reset mail actually sends.

## Group / user ownership (§5e)
Host-provisioned (Tier 0): the `infra` org, the admin human, the bootstrap machine user.
`tofu/zitadel` owns the NetBird project, its OIDC apps, the idp-mgmt user, and the
`netbird_admin` role. The external cluster-tier reconciler owns everything else. NetBird itself
now writes Zitadel **users** (IdP manager) — keep the external reconciler off NetBird-managed
users to avoid two writers.

## Hetzner profile
Inlined in `nix/hetzner.nix`. Drop the inline file once nixpkgs ships its own native module.
