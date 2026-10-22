# Pingvin Share

File sharing in the style of WeTransfer, at `share.luukblankenstijn.nl`:
[Pingvin Share X](https://github.com/smp46/pingvin-share-x), the maintained
fork of the archived Pingvin Share.

| Who | Can |
| --- | --- |
| members of `infra-admins` in Authentik | log in through OIDC, upload, create shares and reverse shares; they are Pingvin admins |
| anyone with a share link | view and download that share, subject to its password, expiry and view limit |
| a named recipient of a share restricted to recipients | download it after logging in with the same email address |

Uploading needs a login: `security.allowUnauthenticatedShares` is off and
password login and sign-up are disabled, so OIDC is the only way in.

## Deployment

`flux/50_apps/pingvin-share`: one replica of `smp46/pingvin-share-x` on port
3000, where the image's own Caddy sends `/api` to the backend and the rest to the
frontend. Longhorn volume `data` on `/opt/app/backend/data` holds the SQLite
database and the uploaded files, so it is in the daily Longhorn backup. The
largest share is 10 GB (`share.maxSize`); the volume is 50 Gi.

There is no forward auth: share links must stay reachable without an Authentik
session, and the app does its own access control.

## Configuration

The configuration is `/opt/app/config.yaml`, rendered by the ExternalSecret
`pingvin-share-config` from OpenBao `authentik/pingvin-share/pingvin-share`
(client ID, secret and issuer, written by `terraform/50_authentik-config`). With
a config file the admin UI cannot change settings; change them in the
ExternalSecret template and restart the pod, which reads the file only at
startup.

## Authentik

`terraform/50_authentik-config/pingvin-share.tf`: OAuth2 provider and application
`pingvin-share`, bound to `infra-admins`. Pingvin reads `groups` from the ID
token and makes members of `infra-admins` admins on every login.

Pingvin refuses logins whose `email_verified` claim is `false`, which is what
Authentik's managed `email` scope always sends. The provider therefore uses its
own scope mapping `Pingvin Share: email, verified` that sends `true`. This is
safe while users cannot change their own email in Authentik; share recipients
are matched by email.
