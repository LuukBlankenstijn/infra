# Operator notes

Pre-deploy checklist, open questions, and one-shot decisions that don't belong in code comments.

## Before first apply
- Replace placeholders in `nix/_config.nix` (`domain`, `kanidmHost`, `netbirdHost`, `cloudflareZone`, `adminEmail`).
- Replace placeholder age recipients in `.sops.yaml` (both `admin_luuk` and `host_netbird`). Generate the admin key with `age-keygen`; the host key is derived from the host's freshly generated `ssh_host_ed25519_key.pub` via `ssh-to-age` (do this after the very first apply, then re-encrypt and re-apply, or pre-generate an age keypair and write the private key into `secrets/host-age-key.txt` so tofu can inject it).
- `sops -e -i secrets/secrets.yaml` once recipients are filled. Replace all `REPLACE_WITH_...` plaintext values with real secrets first.
- Stand up a Garage bucket (`infra-state`, versioning ON), an access key, and update `tofu/host/backend.tf` `endpoints.s3` with the real Garage URL.
- Two Cloudflare tokens, both `Zone:DNS:Edit` on the apex zone — one for tofu CI (Actions secret), one in sops as `acme/cloudflare-token-env` for ACME DNS-01.
- Hetzner Cloud API token as `TF_VAR_hcloud_token` / Actions secret.

## §10.2 — NetBird management API reachability
Open per design. Verify from a hosted GitHub runner that `https://netbird.<domain>` is reachable BEFORE relying on the `netbird-account` module — if not, phase 2 needs an out-of-band path. Quick check: any successful `curl -fsS https://netbird.<domain>/api/users -H "Authorization: Token ..."` from a GH-hosted runner after first apply.

## kanidm CLI command names (1.10.x — verified)
`nix/kanidm/bootstrap.nix` uses two logins (admin + idm_admin) because rights split across them in 1.10: `admin` holds privilege over `idm_oauth2_client_admins`, `idm_admin` does everything else. Verified working subcommand syntax: `--readwrite` (not `--rw`), `service-account create <name> <display> <entry-managed-by-group>`, `service-account api-token generate --output json` returns `.result` (not `.secret`).

## Phase 2 (`tofu/netbird-account/`) first-apply ritual
On a fresh deploy the `netbird_user.luuk` resource fails to create with `"idp manager must be enabled to send user invites"` — NetBird v0.71's user-create path requires an IdP manager, which we don't run (`ManagerType: "none"`). One-time bootstrap:
```sh
tofu apply                                   # creates group/policy/setup-key, fails on user
curl -s -H "Authorization: Token $TF_VAR_netbird_api_token" \
  https://netbird.luukblankenstijn.nl/api/users \
  | jq -r '.[] | select(.email == "me@luukblankenstijn.nl") | .id'
tofu import netbird_user.luuk <id-from-above>
tofu apply                                   # now updates the imported user
```
After that, subsequent applies are clean. The same dance is needed for any new operator added to NetBird's user table outside tofu.

## Reconciler-token handoff
The bootstrap one-shot writes the external reconciler's API token to `/var/lib/kanidm/reconciler-token` (mode 0400, root-owned) on the host. There is no automation to ship it elsewhere. Plan: SSH in once after first boot, `cat` the file, paste it into the cluster-tier reconciler's secret store. Rotate via the same path. If this becomes painful, expose it through `tofu/netbird-account/` outputs using an `ssh` data source.

## NetBird ↔ kanidm caveats (settled in research, recorded here so I don't re-derive)
- kanidm is NOT in NetBird's `IdpManager` provider list → `IdpManagerConfig.ManagerType = "none"` (login-only mode; group sync via JWT `groups` claim).
- kanidm does not implement OAuth2 device-auth (RFC 8628) → `DeviceAuthorizationFlow.Provider = "none"`; desktop clients use PKCE loopback `http://localhost:53000`.
- One confidential oauth2 client (`netbird`) covers dashboard PKCE + desktop PKCE.

## Group ownership (§5e)
Host-provisioned: `infra_admins` only. Everything else (groups, persons beyond the bootstrap admin, additional oauth2 clients, additional service accounts) is reconciled externally against the live kanidm API. Don't share groups across writers.

## Hetzner profile
Inlined in `nix/hetzner.nix`. PR #375551 (native module) has not landed in nixos-26.05. Drop the inline file once nixpkgs ships its own.
