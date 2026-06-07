# Tier 0 Foundation: standalone IdP + NetBird host — design & handoff brief

This document captures **decisions already made** so you (Claude Code) can build without
re-deriving them. Where something is genuinely unresolved it says so and tells you to
**verify rather than guess**. Treat the "rejected options" section (§11) as settled — don't
re-litigate those.

---

## 1. Goal & the core invariant

Build a single standalone **Hetzner Cloud** host that runs the **identity provider
(kanidm)** and the **NetBird management/control plane**, provisioned end-to-end from code.
This is the foundation tier ("Tier 0") that the rest of the infrastructure builds on.

**The invariant that governs every decision:** Tier 0 sits _below_ the k3s cluster in the
dependency graph. The cluster depends on NetBird/kanidm for access and auth, so Tier 0 must
**never** depend back on the cluster (or on the VPN it itself provides). If a choice would
make Tier 0 depend on cluster-tier infrastructure, the choice is wrong. This is why NetBird
and the IdP are pulled out of the cluster in the first place: to avoid the circular
dependency where "cluster down → IdP down → auth down → can't reach cluster to fix it."

**Secondary goal — reproducible cattle:** nuke the host, re-apply, it comes back unattended.
We explicitly accept that generated secrets (e.g. the NetBird OIDC client secret) differ
across rebuilds. We do **not** require byte-identical secrets.

**Self-containment goal (drives §5):** the Tier 0 repo contains _only_ what the foundation
host intrinsically needs — its deployment, the NetBird OIDC client, your own admin user, and
a bootstrap service-account token for the external reconciler. All other identity content
(cluster-service OAuth2 clients, other users/groups/service accounts) is defined and applied
**elsewhere**, reconciled against kanidm's live API. Adding SSO for a cluster app must NEVER
require editing or redeploying Tier 0.

---

## 2. Architecture summary

- **Provisioning:** OpenTofu (`hcloud` provider) creates the server, firewall, SSH key. The
  **nixos-anywhere terraform module** installs the NixOS flake via the **kexec route** (boot
  stock Debian → kexec into the NixOS installer → disko-partition → install the closure). No
  snapshot/image pipeline; for a single host it isn't worth the maintenance.
- **Host OS:** NixOS, flake-based. Import the nixpkgs Hetzner Cloud profile module for the
  virtio/boot/IPv6 plumbing; declare the disk layout with **disko** on top. A cloud VPS is
  uniform virtio hardware, so **no nixos-facter** is needed.
- **Impermanence:** tmpfs root. Persist only `/nix`, `/boot`, ssh host keys, the kanidm state
  directory, and `/var/lib/netbird`.
- **IdP:** kanidm, `kanidmWithSecretProvisioning` build (Kanidm >= 1.8.5 — see §5). Tier 0
  provisions only its bootstrap-minimal identity content via the NixOS `services.kanidm.provision`
  block; everything else is external (§5).
- **NetBird:** the management/control plane runs on this host (NixOS), authenticating against
  the local kanidm via OIDC. This host **is** the control plane — NOT a peer enrolling against
  an external management server.
- **Secrets:** sops-nix. The host's age/ssh key is placed during install via nixos-anywhere
  `--extra-files` so the box can decrypt on first boot.
- **External reconciliation (the decoupling):** both NetBird _account content_ and kanidm
  _non-bootstrap content_ are reconciled from **separate repos/modules against the live APIs**,
  never touching Tier 0. NetBird → its tofu provider; kanidm → the `seanlatimer/kanidm` tofu
  provider (§5).

---

## 3. Repository layout & lifecycle

**One self-contained Tier 0 repo** holding the NixOS flake and the Tier-0 OpenTofu. The main
infra flakes repo tracks `nixos-unstable` and churns frequently; a foundation host must not
ride that churn. Tier 0 gets its own repo, its own pin, its own cadence. A monorepo here is an
_organizational_ dependency, not a _runtime_ one — co-locating does not violate the Tier 0
independence invariant.

```
tier0/                      (the new repo)
├── flake.nix               # nixosConfigurations.netbird-host; STABLE pin (see below)
├── flake.lock
├── nix/
│   ├── host.nix            # the host config
│   ├── disko.nix           # disk layout
│   ├── impermanence.nix    # tmpfs root + persisted paths
│   ├── kanidm.nix          # kanidmWithSecretProvisioning + BOOTSTRAP-ONLY provision block
│   └── netbird.nix         # management server + secret-readback one-shot
├── secrets/                # sops-encrypted
├── tofu/
│   ├── host/               # module A: hcloud + nixos-anywhere + Cloudflare DNS  (phase 1)
│   └── netbird-account/    # module B: NetBird provider                          (phase 2)
└── .github/workflows/      # plan/apply/drift + flake check + update-flake-lock
```

**NOT in this repo:** the external kanidm content reconciler and the external NetBird-client
definitions for cluster services. Those live in a separate repo (cluster-tier), see §5.

**Pin to NixOS stable, not unstable** (e.g. `nixos-25.05`). Security patches without feature
churn. Most of the actual stability comes from this pin; the update bot is secondary.

**Coupling between toolchains:** the tofu host module references the flake output **by
relative path within the repo** — nixos-anywhere installs `.#netbird-host` from the repo root.
No git URL, no cross-repo skew. One commit at one ref fully describes the box.

**Two lockfile concerns:** `flake.lock` (nix side → update bot); `.terraform.lock.hcl` per tofu
module (provider versions → bumped MANUALLY, exact pins; see §6).

**Update bot — notify, don't auto-merge:** `update-flake-lock` (DeterminateSystems action) on a
schedule, opening a PR. Run `nix flake check` (and ideally `nixos-rebuild build` of
`.#netbird-host`) on the bot PR so the notification means "an update that already passed
checks." Merge stays deliberate. Dependabot (now `flake.lock`-aware) is an acceptable fallback.

**Host OS deploy is deliberate, not automatic.** See §8.

---

## 4. Build order — build in tiers, get each green before stacking the next

### Phase 1 — host + control plane (the flake + tofu module A)

1. **OpenTofu module A (`tofu/host/`):** `hcloud_ssh_key`, `hcloud_firewall`, `hcloud_server`
   (stock Debian; pick CX/CAX + location); nixos-anywhere module targeting `ipv4_address`,
   installing `.#netbird-host`, injecting the sops host key via `--extra-files`; plus the
   Cloudflare DNS records (§7). Whatever runs this needs **Nix installed** (closure build) — in
   CI, the nix-installer action.
2. **NixOS flake (`nix/`):** Hetzner profile module + disko; impermanence; sops-nix with the
   injected host key; kanidm + **bootstrap-only** provision (§5); NetBird management pointed at
   local kanidm OIDC, consuming the client secret via the readback one-shot (§5).

**Verify Phase 1 green** — host boots, kanidm up, NetBird management up clean, OIDC wiring works,
you can log in as your bootstrap user — **before** Phase 2, external reconciliation, or CI.

### Phase 2 — NetBird account content (tofu module B, separate state)

3. **OpenTofu module B (`tofu/netbird-account/`):** configured with the NetBird management URL
   (phase-1 output) + an API token (bootstrapped in phase 1, via sops). Reconciles
   `netbird_setup_key` (for _other_ peers), groups, policies, routes. **Separate root module
   with its own state.** Don't configure the NetBird provider from same-apply resources. This is
   a state/provider boundary, not a repo boundary (same repo, two `tofu/` subdirs, two Garage
   state files).

### Phase 3 — external identity content (SEPARATE cluster-tier repo, see §5)

Reconciles all non-bootstrap kanidm content via the `seanlatimer/kanidm` provider. Not part of
Tier 0's repo or lifecycle.

---

## 5. kanidm — the bootstrap/external split (the decoupling)

The whole point: Tier 0 stays minimal and self-contained; identity _content_ lives elsewhere
and is reconciled against the **live kanidm API**, so adding/changing it never redeploys the
foundation host.

### 5a. What Tier 0 provisions (bootstrap-critical only)

Via the NixOS `services.kanidm.provision` block in `nix/kanidm.nix`, ONLY:

- **The NetBird OIDC client** (`systems.oauth2.netbird`, WITHOUT `basicSecretFile` → readonly
  generated secret; see 5d). The box doesn't function without it.
- **Your own admin/person user** — so you can log in to bootstrap and recover on a fresh deploy,
  before any external reconciler has run.
- **A scoped service account + API token for the external reconciler** to authenticate as. This
  is the chicken-and-egg credential: the account the external provider uses CANNOT be created by
  that same provider, so Tier 0 mints it. Give it rights to manage oauth2/persons/groups, NOT
  full `idm_admin`. NOTE: the NixOS provision module historically can't manage service accounts,
  so this likely needs a small bootstrap one-shot (`kanidm service-account ...` + token
  generation) rather than the `provision` block — VERIFY the cleanest path in your kanidm
  version (§10).

Keep the Tier 0 provision block's **`autoRemove` OFF** so it never deletes entities created by
the external reconciler.

### 5b. What lives externally (everything else)

In a SEPARATE cluster-tier repo, an OpenTofu module using the **`seanlatimer/kanidm` provider**
reconciles all other content against the live kanidm API: cluster-service OAuth2 clients, other
persons/groups, additional service accounts. Symmetric with the NetBird account module (separate
repo, runs against the live public API, own state). Reachability is fine — kanidm is public
(DNS-only, public IP, TLS on the box per §7), so the cluster-tier reconciler reaches it without
the VPN. No circular dependency.

### 5c. The provider: `seanlatimer/kanidm`

- **Status:** community/personal namespace, **0.1.x** (current 0.1.10). Author states APIs may
  change before v1.0 and the test suite is incomplete. Acceptable BECAUSE this runs in the
  external reconciler, off the Tier 0 runtime path — worst case is "can't add a new SSO client
  until I work around a bug," not an auth outage.
- **Pin EXACTLY** (`version = "0.1.10"`, not `~> 0.1`) — 0.x has no stability contract, every
  patch can break schema. Commit `.terraform.lock.hcl`. Consider vendoring/mirroring the build
  so a personal-namespace registry entry can't vanish under you.
- **Auth:** `url` + `token` (or `KANIDM_URL`/`KANIDM_TOKEN`). Talks to kanidm's normal REST API —
  no patched build needed. Use the bootstrap service-account token (5a), supplied via **sops**
  (the README shows 1Password; substitute sops — read token from a decrypted file/env in the
  reconciler's CI job). Leave TLS verification ON (`insecure_skip_verify` exists but you have
  real ACME TLS per §7 — do not use it).
- **Requires Kanidm >= 1.8.5** → your `kanidmWithSecretProvisioning` pin must be >= 1.8.5
  (nixpkgs 1.9.x is fine; don't pin below 1.8.5).
- **Fallback (documented, swappable):** if the provider proves too rough, the external slot is
  just "a thing that reconciles kanidm over the API." Drop in **`kanidm-provision`** run
  standalone with ZERO changes to Tier 0. Adopting the provider is not a one-way door. (Note a
  fork-fix of a tofu provider is a bigger lift — Go + plugin framework — than rebasing the small
  `kanidm-provision` patch; budget accordingly.)

### 5d. Resources & the confirmed secret readback

Confirmed from the provider README/registry:

- **`kanidm_oauth2_basic`** (confidential) and **`kanidm_oauth2_public`** (PKCE/SPA) clients.
  **CONFIRMED: `kanidm_oauth2_basic` exposes `client_secret` as a sensitive readable attribute**
  — this is the make-or-break for the readonly-secret flow, and it works. Declare the client in
  the external repo, `output` its `client_secret`, deliver to the cluster app. (Attribute is
  `client_secret`, not `basic_secret`.)
- **`kanidm_service_account`** exposes `api_token` (sensitive) — manages downstream service
  accounts AND mints their tokens. Closes the gap the NixOS provision module couldn't.
- **`kanidm_person`** supports `generate_initial_credential_reset_token` +
  `initial_credential_reset_token_ttl`, token as sensitive output → persons come up with a
  time-boxed reset link instead of the no-credential state that plagued `kanidm-provision`.
- Registry listing also showed `kanidm_group`, `kanidm_group_members`, `kanidm_account_policy`,
  `kanidm_system_denied_names`, `kanidm_application`.

### 5e. Group ownership — DISCREPANCY, resolve before sharing groups

The README shows a whole-list-owning `kanidm_group { members = [...] }` and NO
`kanidm_group_members`; the registry schema listed `kanidm_group_members` described as managing a
**subset** of membership without owning the whole list. These disagree (README likely staler than
the published 0.1.10). **Trust the registry schema over the README**, but VERIFY which group
resources actually exist in 0.1.10.

**Design rule regardless of the outcome:** do NOT share groups across the two writers (Tier 0
bootstrap vs external reconciler). Tier 0 owns its bootstrap groups entirely; the external
reconciler owns all others. Then whole-list-vs-subset stops mattering and there's no clobber risk.

### 5f. Recommended pre-build smoke test (settles all open kanidm questions in ~10 min)

Stand up a throwaway kanidm (>= 1.8.5), point `seanlatimer/kanidm` 0.1.10 at it, and confirm
empirically: (1) `kanidm_oauth2_basic.client_secret` actually populates; (2)
`kanidm_service_account.api_token` works as a provider `token`; (3) whether `kanidm_group_members`
exists. This replaces guessing from two disagreeing docs.

---

## 6. OpenTofu state & providers

- **Backend:** Garage (S3-compatible), bucket **versioning enabled**, OpenTofu **state
  encryption** on (NetBird setup keys are sensitive values in state).
- **Locking — RESOLVED:** `use_lockfile` is **NOT usable**. Confirmed: Garage has
  read-after-write consistency but **no S3 conditional writes (`If-None-Match`)**, which
  `use_lockfile` requires. Decision:
  - **No backend locking.** Serialize applies with a GitHub Actions `concurrency` group
    (per-module key). Single-person, CI-only applies → removes the concurrency locking would
    guard against.
  - **Operating rule:** applies go through CI, not ad-hoc local runs racing CI.
  - **Recovery net:** Garage state versioning to roll back a clobbered state.
- **Provider pinning:** pin EVERY provider hard and exact for the young ones — `netbird` (0.0.x)
  and `seanlatimer/kanidm` (0.1.10). Bumps are manual, deliberate, changelog-read events.
- **Cluster-tier note (NOT Tier 0):** cluster-tier tofu can use the `pg` backend with Postgres
  advisory locking via the existing CNPG — real locking. Unavailable to Tier 0 (Postgres is
  in-cluster → circular). Cluster tier only.

---

## 7. Cloudflare DNS

DNS-as-code for the Tier-0 dashboard hostnames (`id.example.com` kanidm, `netbird.example.com`).
Provider: official `cloudflare/cloudflare` (mature, unlike the young identity providers).

- **Lives in tofu module A (`tofu/host/`).** Records point at `hcloud_server.ipv4_address`
  (phase-1 output); provider config depends only on an API token, not same-apply resources, so
  it plans fine alongside hcloud. Fold into A unless DNS later sprawls.
- **Reconciles to current IP automatically** — DNS lives in Cloudflare + tofu state, not on the
  box; impermanence doesn't touch it. Nuke host → phase 1 re-applies → A record updates.
- **Token — least privilege:** `Zone:DNS:Edit` on the specific zone (NOT a global key). In sops;
  Actions secret for CI. Same token does double duty: DNS records AND the DNS-01 ACME challenge.
- **DNS-only (grey cloud), NOT proxied — terminate TLS on the host.** Proxied would put
  Cloudflare's edge in the access path to the IdP/NetBird management — a dependency in front of
  the thing that gates everything else (wrong for a foundation tier; and NetBird's data plane
  isn't HTTP and must never be proxied). DNS-only keeps Cloudflare a pure resolver; terminate TLS
  on the box via ACME DNS-01 using the same Cloudflare token (valid certs, no port 80, no
  proxying).
- **Tier-0 dashboards are public-but-TLS'd at the public IP.** Do NOT point IdP/NetBird-management
  hostnames at the host's NetBird IP — circular. Cluster-tier service dashboards are the ones you
  hide behind NetBird-only access. Keep the split clear.

---

## 8. CI / workflows

**Runners — hosted, permanently, for Tier 0.** GitHub-hosted, and do NOT migrate Tier 0 to
self-hosted later. A self-hosted runner lives inside the infra and risks being inside the loop
Tier 0 provisions. Hosted runners are deliberately external. _(Self-hosted runners for OTHER
projects — cluster-tier tofu incl. the external kanidm reconciler, app deploys — are fine and the
right way to dodge GitHub usage limits. Hosted-only is specific to Tier 0.)_

**Two tofu modules in one repo → path-filter** so `tofu/host/` and `tofu/netbird-account/` trigger
their own plan/apply. Ordering (host before account) only matters on from-scratch builds.

**Workflows:**

- **PR → `tofu plan`** (per module, path-filtered), posted as a PR comment. Review gate.
- **merge → `tofu apply`** (per module, path-filtered); optional GitHub environment + required
  reviewers. The **netbird-account** module is the live-reconciler — safe to apply on push (API
  state).
- **schedule → `tofu plan -detailed-exitcode`** on both modules; exit 2 = drift → alert (detect,
  don't auto-correct). The account module's nightly plan catches dashboard fiddling.
- **`nix flake check` on PRs** (and on `update-flake-lock` bot PRs) — nix build-verification gate.
- **Host OS deploy → DELIBERATE, NOT on push.** nixos-anywhere/nixos-rebuild is
  `workflow_dispatch` (manual). Tofu account reconcile-on-push fine; an OS rebuild hitting the
  running access layer wants a human pressing go. **Do not let "on push" blanket-apply a
  `nixos-rebuild`.**
- **`concurrency` group on every apply workflow** (locking substitute, §6), per-module keys.

**Secrets:** Hetzner token + NetBird API token as Actions secrets. (The external kanidm
reconciler's CI lives in the OTHER repo and gets the kanidm service-account token via sops there.)

---

## 9. Impermanence note

kanidm's sqlite DB cannot live on tmpfs — its state directory MUST be persisted. The host is
stateful regardless of any secret-handling choice; persistence isn't a regression we introduce,
it's inherent to running kanidm. Persist the kanidm state dir alongside `/var/lib/netbird`, ssh
host keys, `/nix`, `/boot`.

---

## 10. Open items — VERIFY, do not guess

1. ~~Garage conditional-write support~~ — **RESOLVED**: not supported (§6).
2. **Is the NetBird management API reachable WITHOUT the VPN** from the hosted runner / wherever
   phase 2 runs? The circular-dependency check. If management is VPN-only, phase 2 (and other
   peers' setup keys) needs an out-of-band path. RESOLVE EARLY — it's the only open item that
   could force a structural change.
3. **NetBird ↔ kanidm OIDC specifics:** confirm the exact oauth2 client shape NetBird expects
   (public vs confidential, PKCE, scope/claim maps for group→role, headless/device-code
   enrollment needs). Both projects' current docs.
4. **nixpkgs Hetzner profile module:** confirm whether the native work (PR #375551 —
   `hcloud-upload-image`, `systemd-network-generator-hcloud`, `virtualisation/hcloud`) has landed
   in your channel; otherwise vendor from `outskirtslabs/nixos-hetzner` for virtio/boot/IPv6.
5. **Minting the reconciler's service account in Tier 0** (5a): confirm the cleanest way to create
   a scoped service account + token in your kanidm version (likely a bootstrap one-shot, since the
   NixOS provision module may not manage service accounts).
6. **`seanlatimer/kanidm` 0.1.10 behaviors** (5f smoke test): `client_secret` populates;
   `service_account.api_token` works as a provider token; whether `kanidm_group_members` exists
   (the README/registry group-resource discrepancy, 5e).
7. **`services.kanidm.provision` current option surface** in the pinned nixpkgs — confirm option
   names (`idmAdminPasswordFile`, `systems.oauth2.<name>` fields) match what you write.

---

## 11. Explicit non-goals / rejected options (settled — do not revisit)

- **Byte-identical secrets across rebuilds** — not required; readonly generated secrets are fine.
- **oauth2-secret patch (`basicSecretFile`)** — not used; read the generated secret instead
  (NixOS side AND via the provider's `client_secret` output externally).
- **Capture-the-generated-admin-password on first boot** — rejected; sops + `idmAdminPasswordFile`
  (no statelessness gain, more bespoke glue).
- **All kanidm content in Tier 0's flake** — rejected; that couples content to the foundation
  deploy. Only bootstrap-critical content in Tier 0; the rest reconciled externally (§5).
- **External flake imported into Tier 0 to contribute provision entries** — rejected. It tidies
  the repo but does NOT decouple the lifecycle: imported entries still evaluate at Tier 0 build
  time and apply at Tier 0 activation, so changing them still redeploys the foundation host. The
  live-API reconciliation approach (§5) is what actually decouples.
- **Snapshot/image build pipeline** — not used; kexec via nixos-anywhere is simpler for one host.
- **nixos-facter** — not needed on a uniform virtio VPS.
- **NetBird provider in the same apply/module as the host** — rejected; separate phase-2 module +
  state.
- **`use_lockfile` / DynamoDB / CNPG-`pg` backend for Tier 0 locking** — rejected (Garage has no
  conditional writes; CNPG is in-cluster → circular). CI concurrency + Garage versioning instead.
- **Self-hosted runners for Tier 0** — rejected; hosted-only to stay out-of-band.
- **Auto-deploying the host OS on push** — rejected; manual `workflow_dispatch`.
- **Tier 0 in the main unstable flakes repo** — rejected; separate repo, stable pin.
- **Proxied (orange-cloud) Cloudflare for Tier-0 dashboards** — rejected; DNS-only + TLS on box.
- **Sharing kanidm groups across Tier-0 bootstrap and the external reconciler** — rejected; each
  side owns its own groups to avoid clobbering (§5e).
