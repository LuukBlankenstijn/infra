# Backups

Everything is written to Hetzner Object Storage, `https://fsn1.your-objectstorage.com`
(region `fsn1`).

| Data | Mechanism | Destination | Schedule | Retention |
| --- | --- | --- | --- | --- |
| Postgres | Barman Cloud plugin: WAL archive + base backups | `s3://luuk-postgres/` | WAL continuously, base backup 03:00 | 30 days |
| MariaDB | `PhysicalBackup` | `s3://luuk-mariadb/base/` | base backup 03:00 | 30 days (`720h`) |
| Longhorn volumes in recurring-job group `default` | `RecurringJob` `daily-backup` | bucket `luuk` (`s3://luuk@fsn1/`) | 02:30 | 14 backups |
| Same volumes, on the node | `RecurringJob` `daily-snapshot` | local snapshots | 03:03 | 31 snapshots |
| OpenTofu state | S3 backend, encrypted | bucket `luuk`, `<root>/terraform.tfstate` | every apply | - |

The cluster's desired state, the sops files and the SealedSecrets are in git.

## Postgres

`flux/40_services/postgres/object-store.yaml`:

| Object | Does |
| --- | --- |
| `ObjectStore` `postgres` | `destinationPath: s3://luuk-postgres/`, gzip for WAL and data, `retentionPolicy: 30d` |
| `Cluster.spec.plugins` | `barman-cloud.cloudnative-pg.io` with `isWALArchiver: true` |
| `ScheduledBackup` `postgres-daily` | `method: plugin`, `0 0 3 * * *` (six fields, seconds first), `immediate: true` |
| `ExternalSecret` `postgres-s3` | bucket key from OpenBao `s3/postgres/postgres` (`40_s3-buckets`) |

`serverName` is unset, so Barman stores under `s3://luuk-postgres/postgres/`.
The plugin sidecar sets `AWS_REQUEST_CHECKSUM_CALCULATION` and
`AWS_RESPONSE_CHECKSUM_VALIDATION` to `when_required`, so boto3 only adds
checksums where the S3 API requires them.

```sh
kubectl -n postgres get backups
kubectl cnpg status -n postgres postgres
```

### Restore

Bootstrap a new `Cluster` from the object store; it can target any time inside
the retention window:

```yaml
spec:
  bootstrap:
    recovery:
      source: origin
      recoveryTarget:
        targetTime: "<timestamp>"
  externalClusters:
    - name: origin
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: postgres
          serverName: postgres
```

The restored cluster must archive under a different `serverName` (or bucket):
two clusters archiving to one prefix corrupt each other's WAL timeline.

## MariaDB

`flux/40_services/mariadb/backup.yaml`:

| Object | Does |
| --- | --- |
| `PhysicalBackup` `mariadb-daily` | `mariadb-backup` base backup, `0 3 * * *` (five fields), `immediate: true`, gzip, `maxRetention: 720h`, prefix `base` |
| `PointInTimeRecovery` `mariadb` | binlog archive to prefix `binlog`, referenced by the `MariaDB` through `pointInTimeRecoveryRef`; inactive, see below |
| `ExternalSecret` `mariadb-s3` | bucket key from OpenBao `s3/mariadb/mariadb` |

`mariadb-daily` passes `--disable-ssl-verify-server-cert`: it connects to the
server by its Service address, which the certificate does not name.

Binary logs are not archived. mariadb-operator archives binlogs only in its
asynchronous replication topology; this instance is standalone, so the server
runs with `log_bin` off and the `PointInTimeRecovery` object does nothing. A
restore goes back to the last 03:00 base backup: up to a day of writes is lost.

### Restore

Create a new `MariaDB` with
`bootstrapFrom.backupRef: {name: mariadb-daily, kind: PhysicalBackup}` (the
newest backup) or add `targetRecoveryTime` to pick the newest backup before that
time. Reuse `rootPasswordSecretKeyRef` `mariadb-root`: the restored data has the
original root password.

## Longhorn

`flux/30_config/longhorn`:

- `BackupTarget` `default`: `s3://luuk@fsn1/`, credentials from the SealedSecret
  `longhorn-system/backup-credentials`, polled every 5 minutes.
- `RecurringJob`s `daily-backup`, `daily-snapshot` and `fs-trim` (Sundays 00:00),
  all in group `default`. Longhorn puts every volume without recurring-job
  labels of its own in that group, so every volume on the `longhorn`
  StorageClass is covered: OpenBao's Raft data, `netbird-data`, and the
  application volumes.
- StorageClass `longhorn-single` (one replica) sets `recurringJobSelector` to the
  empty group `none`. The Postgres and MariaDB volumes use it: a Longhorn backup
  of a running database is only crash-consistent and duplicates the database
  backups above.

The default VolumeSnapshotClass `longhorn-backup-vsc` (`type: bak`) turns a CSI
`VolumeSnapshot` into a Longhorn backup in the same target.

### Restore

Restore a volume from its backup in the Longhorn UI
(`https://longhorn.luukblankenstijn.nl`, behind Authentik), then bind it to the
workload's PVC through a PV that names the restored volume.

## Restore test

Every Sunday 05:00 (Europe/Amsterdam) CronJob `restore-test/restore-test`
(`flux/40_services/restore-test`) restores both databases next to production
and deletes the copies again:

1. **Postgres.** It writes the current time to `restore_test.marker` in database
   `postgres`, switches WAL and waits until that segment is archived. It then
   creates Cluster `postgres/restore-test`, bootstrapped from ObjectStore
   `postgres` (`serverName: postgres`) without a WAL archiver of its own, so it
   only reads the archive. The copy must contain the marker and every database
   and table of production.
2. **MariaDB.** It creates MariaDB `mariadb/restore-test` from the newest
   `mariadb-daily` backup. The copy must contain every database and table of
   production, apart from ones created since 03:00.

The script is `run.sh` in ConfigMap `restore-test`; it runs in `alpine/k8s` as
ServiceAccount `restore-test/restore-test`, whose Roles in `postgres` and
`mariadb` named `restore-test-runner` (CNPG already uses `restore-test` for the cluster's own Role), allow only creating and deleting those two kinds plus exec into pods.
It checks over `kubectl exec` with the database images' own clients. The copies
use `longhorn-single`, which no Longhorn backup job picks up. The copies and
their PVCs (mariadb-operator keeps a StatefulSet's PVC when the `MariaDB` is
deleted) are removed on exit and again before each run.

To run it now:

```sh
kubectl -n restore-test create job --from=cronjob/restore-test restore-test-manual
kubectl -n restore-test logs -f job/restore-test-manual
```

`RestoreTestFailed` fires when the newest run failed, `RestoreTestStale` when no
run succeeded in 8 days.

## OpenBao contents

OpenBao's Raft data is a Longhorn volume and is only readable with the seal key
in the SealedSecret `openbao/openbao-seal`. Independently, every value OpenTofu
writes to OpenBao is also in that root's state: generated values (passwords,
NetBird keys, the Authentik bootstrap token, client secrets) come from `random_*`
resources, the rest from sops. Re-applying `40_openbao-config`, `40_databases`,
`40_s3-buckets` and `50_authentik-config` against an empty OpenBao rewrites the
same values.

## Not covered

- **`local-path` volumes.** k3s's `local-path` is also a default StorageClass. A
  PVC without `storageClassName` can land there, outside Longhorn and every
  backup, so every PVC must set its class.
- **One provider, one region.** Database backups, Longhorn backups and OpenTofu
  state are all in Hetzner Object Storage `fsn1`. There is no second copy.
- **The node.** k3s's own datastore and the Longhorn local snapshots live on
  `home-server`'s disk. The cluster is rebuilt from git with
  `20_cluster-bootstrap` and Flux, then data is restored as above.
- **The admin age key.** It is the only recipient of every `secrets/*.yaml`
  except the host files (`edge.yaml`, `home-server.yaml`, `home-gateway.yaml`,
  `openbao/{edge,home-gateway}.yaml`), which a host key can also open. Without
  it the state passphrase, the sealing key and the
  external credentials are gone, and with the sealing key every SealedSecret.
- **MariaDB point-in-time recovery.** See [MariaDB](#mariadb): only the nightly
  base backups exist.
- **Longhorn restore tests.** Only the databases are test-restored.

Failed, stale and missing backups, a stalled WAL archive and a failed or
overdue restore test alert in group `data` (see
[Alerting](../observability/alerting.md)).
