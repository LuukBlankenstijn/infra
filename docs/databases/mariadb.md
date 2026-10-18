# MariaDB

One `MariaDB`, `mariadb/mariadb` (`flux/40_services/mariadb`), managed by
mariadb-operator (charts `mariadb-operator-crds` and `mariadb-operator`, namespace
`mariadb-operator`, `controllers` layer): one replica, image
`mariadb:12.3.3`, 5 Gi on `longhorn-single`. Applications share it, one user and
database each. It stays on 12.x: Renovate skips MariaDB major versions, because
mariadb-operator supports up to 12.3.

## Adding a database

`terraform/40_databases/mariadb.tf` owns every application user, database, grant
and credential:

```hcl
mariadb_databases = {
  grimmory = { namespace = "grimmory" }
}
```

Per entry the root generates a 32-character password, creates user `<name>@%`
with `REQUIRE SSL`, the database, and a grant of the application privileges on
it, then writes `username`, `password`, `dbname`, `host`
(`mariadb.luukblankenstijn.nl`) and `port` to OpenBao
`mariadb/<namespace>/<database>`. The namespace reads it through its `mariadb`
SecretStore (role `mariadb-<namespace>`).

OpenTofu connects as `provisioner`. The operator creates that user with a
generated password in Secret `mariadb/mariadb-provisioner`, and the `Grant`
`provisioner` gives it the same privileges on `*.*` plus `CREATE USER`, with
grant option.

## TLS

The operator's own TLS is off (`tls.enabled: false`). Instead the cert-manager
Certificate `mariadb-tls` (Let's Encrypt, `mariadb.luukblankenstijn.nl`) is
mounted at `/etc/mariadb-tls` and set as `ssl_cert`/`ssl_key` in `myCnf`.
MariaDB does not reload certificates by itself, so the CronJob `tls-reload` runs
`FLUSH SSL` as root against `mariadb.mariadb.svc.cluster.local` daily at 04:30.

Inside the cluster CoreDNS rewrites `mariadb.luukblankenstijn.nl` to
`mariadb.mariadb.svc.cluster.local`; Grimmory connects with
`sslMode=verify-full`.

The Service `mariadb` is a LoadBalancer on `192.168.1.78:3306`. OpenTofu connects
there with `tls = "skip-verify"`, since the address does not match the
certificate name.

Backups are nightly physical backups only; binary logs are not archived (see
[Backups](backups.md#mariadb)).
