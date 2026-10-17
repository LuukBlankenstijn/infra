# AGENTS.md

Home infrastructure in one repository. Read `docs/index.md` first; it links to
every area.

## Layout

| Path | What |
| --- | --- |
| `flux/clusters/home` | FluxInstance and one Kustomization per layer |
| `flux/NN_<layer>/` | what the cluster runs; the number is the apply order (`dependsOn`, `wait: true`) |
| `terraform/NN_<root>/` | OpenTofu roots, applied by hand from this machine; S3 state, encrypted |
| `nix/hosts/<host>/` | NixOS hosts `edge`, `home-server`, `home-assistant`, built with `nix-config.lib.mkHost` |
| `secrets/` | sops files (admin key; host files also to that host's key) |
| `docs/` | mkdocs site, `nix build .#docs` (strict) |

Shared NixOS modules live in the separate repo `LuukBlankenstijn/nix-config`
(flake input `nix-config`). Change modules there, then bump the input here.

## Rules

- **Docs are part of every change.** Update the matching page in `docs/` in the
  same commit. Docs describe the current state only, not history. A new page
  goes into `mkdocs.yml` `nav`. `nix build --no-link .#docs` must pass.
- **Alerting is part of every change.** When you add or change something that
  can break (a service, a backup, a host, a scrape target, a certificate, a
  tunnel), add or update its alert rules and metrics in the same change:
  - rules: `flux/50_apps/observability/rules/<group>.yaml` (PrometheusRule;
    LogQL rules carry label `rules.luukblankenstijn.nl/backend: loki`);
  - every alert needs `severity` (`critical`, `warning`, `info`) and `group`;
  - metrics: prefer the chart's ServiceMonitor/PodMonitor, else the
    `prometheus.io/scrape` pod annotation (the port must be a declared
    `containerPort`);
  - check expressions with `promtool check rules` and against real metric names
    in Mimir;
  - stale-data alerts need an `or absent(...)` so a vanished metric still fires;
  - update `docs/observability/alerting.md`.
- **No plaintext secrets.** The repo is public. Secrets come from OpenBao via
  external-secrets, or from sops. Filenames matching `*secret.yaml` are ignored
  by git; use `secret-stores.yaml` / `external-secrets.yaml`. Before every push,
  scan staged changes for `BEGIN .*PRIVATE KEY`, `hvs.`, `nbp_`, `tk_` tokens and
  `kind: Secret` with data.
- **No comments in code**, unless unavoidable.
- **Remote actions need permission** (pushes, applies, host switches) unless the
  user has granted them in the conversation.
- Pin chart and image versions; Renovate bumps them (`renovate.json`).

## Alert groups

Each `group` is an ntfy topic `alerts-<group>` on `https://ntfy.luukblankenstijn.nl`:

| Group | For |
| --- | --- |
| `infra` | nodes, edge, disks, GPU, Kubernetes resources and storage |
| `platform` | Flux, certificates, Traefik, OpenBao, external-secrets, comin, frp tunnel, device certificates |
| `data` | Postgres, MariaDB, Longhorn and their backups |
| `apps` | public endpoints, workloads |
| `security` | logins, from logs |
| `meta` | the monitoring and alerting stack itself |

A new group needs a route and receiver in
`flux/50_apps/observability/alertmanager/external-secrets.yaml` and an
`alerts-*` subscription on the phone.

## Working

- `direnv allow` loads the dev shell, `KUBECONFIG=.kube/config`, `BAO_ADDR` and
  sops-backed variables. Each tofu root's `.envrc` adds its own.
- Flux syncs `main`. After a push:
  `kubectl -n flux-system annotate gitrepository flux-system reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite`.
  A failing HelmRelease blocks its whole layer.
- NixOS hosts deploy themselves with comin from `main`. Release jumps: use
  `nixos-rebuild boot` and reboot, not `switch`.
- `nix flake check` must pass (CI runs it and builds every host).
