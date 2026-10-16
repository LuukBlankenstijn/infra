# Postgres

One CloudNativePG `Cluster`, `postgres/postgres` (`flux/40_services/postgres`):
one instance, PostgreSQL 18, 20 Gi on `longhorn-single`. Every application
shares it; each gets its own role and database. The operator (chart
`cloudnative-pg`) and the Barman Cloud plugin run in namespace `cnpg` from the
`controllers` layer.

## Adding a database

`terraform/40_databases/postgres.tf` owns every application role, database and
credential. One map entry is the whole change:

```hcl
postgres_databases = {
  authentik      = { namespace = "authentik" }
  netbird        = { namespace = "netbird" }
  netbird_events = { namespace = "netbird" }
  netbird_idp    = { namespace = "netbird" }
  vaultwarden    = { namespace = "vaultwarden" }
}
```

Per entry the root generates a 32-character password, creates the login role
and the database it owns, and writes `username`, `password`, `dbname`, `host`
(`postgres.luukblankenstijn.nl`) and `port` to OpenBao
`postgres/<namespace>/<database>`. The namespace reads it through its `postgres`
SecretStore (role `postgres-<namespace>`, see
[OpenBao](../cluster/openbao.md#roles-and-policies)). Nothing per-application
lives in the `postgres` namespace.

OpenTofu connects as `provisioner`, the `initdb` owner with `CREATEDB` and
`CREATEROLE`, whose password it reads from the CNPG-generated Secret
`postgres/postgres-app`. Superuser access is disabled.

## TLS and names

The server certificate is `postgres-tls`, a Let's Encrypt certificate for
`postgres.luukblankenstijn.nl` (DNS-01, ClusterIssuer `letsencrypt-dns`). It
carries the `cnpg.io/reload` label, so a renewal is picked up without a restart.
`postgres-server-ca` (`serverCASecret`) holds the ISRG root certificates that
issue it. `pg_hba` rejects every non-TLS connection.

Inside the cluster CoreDNS rewrites `postgres.luukblankenstijn.nl` to
`postgres-rw.postgres.svc.cluster.local` (`flux/30_config/coredns/custom.yaml`),
so applications connect by that name with `sslmode=verify-full` against the
system roots. Outside the cluster the name resolves through the wildcard record
to the edge, which does not forward 5432.

## LAN access

The CNPG-managed Service `postgres-lan` (`managed.services.additional`,
`selectorType: rw`) is a LoadBalancer on `192.168.1.78:5432`. OpenTofu connects
there with `sslmode=require`: the address does not match the certificate name,
which only resolves to the database inside the cluster.

```sh
kubectl cnpg psql -n postgres postgres
```

## Server parameters

TCP keepalives (`idle 60`, `interval 10`, `count 3`) and
`idle_in_transaction_session_timeout = 60000` drop dead and stuck sessions.

## Backups

WAL archiving and a daily base backup to `s3://luuk-postgres/`, see
[Backups](backups.md#postgres). The volume class `longhorn-single` keeps Longhorn
recurring jobs off this volume.
