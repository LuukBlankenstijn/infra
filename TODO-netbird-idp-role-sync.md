# TODO: Auto-assign NetBird account role from IdP group membership

**Status:** not started — scoping/spec only. Pick this up as a fresh task.
**Type:** upstream contribution to NetBird (`netbirdio/netbird`), not an infra-base change.

---

## Goal

Make a user's **NetBird account role** (`owner` / `admin` / `user` / `network_admin` /
`billing_admin` / `auditor`) be driven by their **IdP group membership**, instead of having to
set each user's role manually in the NetBird dashboard/API. I.e. "members of IdP group X get
NetBird role Y", evaluated on IdP sync / login.

This is the natural companion to NetBird's existing **JWT group sync** (which already maps an IdP
`groups` claim → NetBird *group membership*, but **not** → account *role*).

## Why (our context)

This infra (`infra-base`) runs **Zitadel** as the IdP for **NetBird** (self-hosted, NetBird
mgmt `v0.71.4` on the host `id.luukblankenstijn.nl` / `netbird.luukblankenstijn.nl`). We decided:

- **NetBird groups + policies** are declarative in `tofu/netbird-account` (they must exist before
  anyone logs in, so policies can reference them — see the ordering problem in upstream #4882).
- **Group *membership*** should be IdP-driven via JWT group sync (Zitadel project role →
  `groups` claim via a `zitadel_action`, matched by name to the NetBird group).

The gap: there is **no way to drive the NetBird account *role* from a group/claim**. Today a new
SSO user defaults to `user`; promoting someone to `admin` is a manual per-user action (dashboard,
or `netbird_user.role` in tofu, which then needs the import-on-first-login dance). We want
Zitadel to be the single source of truth for "who is a NetBird admin".

Key distinction (don't conflate): NetBird **group** = network/policy membership (can be
IdP-driven today); NetBird **role** = management permissions (NOT IdP-driven — this TODO).

## Upstream landscape (searched 2026-06-12)

- **#5390 "Auto-assign User Role from IdP Group membership"** — **THE issue. Open,
  `feature-request`, opened 2026-02-19, 0 comments, no PR.** Spec matches ours (group→role map,
  single-role, highest-priority-wins). **Engage this issue — do NOT open a duplicate.**
- #4107 — user asking how to control NetBird access via Zitadel roles (only answered with the
  clunky "separate orgs/projects" workaround) → demand signal.
- #5502 "More granular Admin Rights" — `feature-request`, related.
- #4882 — "Define Policies Prior to IdP Provisioning" — the ordering pain we already hit.
- #2685 — "Cant assign manually created groups via jwt group sync" — relevant to match-by-name.
- #1713 / #3590 — Zitadel group-sync specifics, useful background.

## How NetBird's existing JWT group sync works (grounding)

Account settings already include: `jwt_groups_enabled`, `jwt_groups_claim_name` (e.g. `groups`),
`groups_propagation_enabled` (user's groups → their peers), `jwt_allow_groups` (allowlist).
On auth/sync NetBird reads the claim, **matches group by name** (creates if missing), and sets
the user's JWT-sourced membership (reconciled each login). The sync/propagation logic lives in
`management/server/account.go` (`warmupIDPCache`, group propagation) and the IdP managers under
`management/server/idp/` (e.g. `zitadel.go`). The account role lives on the user object.

## Proposed design (follow #5390)

- New account setting: a **`group → role` mapping** (plus a default role).
- On IdP sync / user provisioning / login: evaluate the user's group memberships, pick the
  **single highest-priority role** (define a fixed priority order, e.g. owner > admin >
  network_admin > billing_admin > auditor > user), set `user.Role`.
- **Single-writer:** when enabled, the IdP owns the role — surface that this conflicts with
  manually-set roles / `netbird_user.role` in tofu (document, or make it opt-in per account).
- Don't touch the `owner` (account owner is special — never demote via sync).

## Implementation scope (where the work is)

A *complete* feature spans layers (calibrate "easy" accordingly — core logic is trivial, spread
is the cost):

1. **Account settings schema** — NetBird mgmt API is **gRPC/protobuf**; add the mapping setting
   → `.proto` + regenerated code.
2. **Store migration** — persist the new setting.
3. **Server sync logic** — `management/server/account.go` sync path: compute highest-priority
   role from the user's groups and apply it. Reuse the same trigger points as group propagation.
4. **API/docs** — expose the setting via the mgmt API (so it's tofu-manageable via
   `netbird_account_settings`, once the provider supports it).
5. **Dashboard** (separate repo `netbirdio/netbird-dashboard`) — UI for the mapping. **MVP can
   skip this** (configure via API/tofu first, dashboard later).

**Suggested MVP:** backend + API only (settings + sync logic + migration), configurable via API.
Dashboard as a follow-up.

## First steps for whoever picks this up

1. Read the code: `management/server/account.go` (`warmupIDPCache` + group propagation),
   `management/server/idp/zitadel.go`, the account-settings proto, and how `jwt_groups_enabled`
   is plumbed end-to-end (use it as the template — role mapping mirrors group sync closely).
2. **Comment on #5390** with our Zitadel use case + intent to implement, and ask the maintainers
   where they want the mapping config to live / single-vs-multi-role semantics, BEFORE coding.
3. Build the MVP backend + migration; add tests next to the existing JWT-group-sync tests.

## Test environment (ours)

- Live stack to validate against: Zitadel at `https://id.luukblankenstijn.nl`, NetBird mgmt at
  `https://netbird.luukblankenstijn.nl` (this repo deploys it).
- Zitadel already has a `NetBird` project with a role (currently `netbird_admin`; rename to match
  a NetBird group name like `admins` when wiring group sync) and a `zitadel_action` that flattens
  roles → `groups` claim (`tofu/zitadel/main.tf`). Grant the role to a test user and confirm the
  token carries `groups` (this claim emission is still unverified — see NOTES.md).
- NetBird groups/policies are in `tofu/netbird-account/`.

## Related decision (not blocking this TODO)

We are leaning toward enabling JWT **group** sync (membership) with NetBird-owned group objects +
policies. That work is separate from this role-sync feature but shares the same code paths and
test setup. If pursued, drop the human user's `auto_groups` in tofu so the claim is the single
writer of membership (keep setup-key `auto_groups` for headless servers).
