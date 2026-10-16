# Backups

Everything is written to Hetzner Object Storage, `https://fsn1.your-objectstorage.com`
(region `fsn1`).

| Data | Mechanism | Destination | Schedule | Retention |
| --- | --- | --- | --- | --- |
| Postgres | Barman Cloud plugin: WAL archive + base backups | `s3://luuk-postgres/` | WAL continuously, base backup 03:00 | 30 days |
| MariaDB | `PhysicalBackup` + `PointInTimeRecovery` binlog archive | `s3://luuk-mariadb/` (`base/`, `binlog/`) | base backup 03:00, binlogs as they close | 30 days (`720h`) |
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
| `PointInTimeRecovery` `mariadb` | binlog archive, prefix `binlog`, gzip, base backups from `mariadb-daily`; referenced by the `MariaDB` through `pointInTimeRecoveryRef` |
| `ExternalSecret` `mariadb-s3` | bucket key from OpenBao `s3/mariadb/mariadb` |

`mariadb-daily` passes `--disable-ssl-verify-server-cert`: it connects to the
server by its Service address, which the certificate does not name. Archive
state is in the `MariaDB` status:

```sh
kubectl -n mariadb get mariadb mariadb -o jsonpath='{.status.pointInTimeRecovery}'
```

### Restore

Create a new `MariaDB` with `bootstrapFrom.pointInTimeRecoveryRef: {name: mariadb}`
and a `targetRecoveryTime`. It must archive to a different binlog prefix: the
prefix has to be empty when archiving starts.

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
  except `edge.yaml`. Without it the state passphrase, the sealing key and the
  external credentials are gone, and with the sealing key every SealedSecret.
- **Verification.** Nothing in the repository restores a backup on a schedule or
  alerts on a failed backup or a stalled archive.
