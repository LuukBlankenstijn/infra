# NetBird reverse proxy

The Deployment `netbird/reverse-proxy` (`flux/50_apps/netbird/reverse-proxy.yaml`)
publishes services through NetBird's reverse-proxy feature. It registers with
management as the private proxy cluster `proxy.luukblankenstijn.nl`.

| Setting | Value |
| --- | --- |
| `NB_PROXY_DOMAIN` | `proxy.luukblankenstijn.nl` |
| `NB_PROXY_PRIVATE` | `true` |
| `NB_PROXY_MANAGEMENT_ADDRESS` | `http://netbird-service:81`, in-cluster plaintext gRPC (`NB_PROXY_ALLOW_INSECURE`) |
| `NB_PROXY_TOKEN` | Secret `netbird-reverse-proxy-token`, from OpenBao `secret/netbird/reverse-proxy` |
| `NB_PROXY_ADDRESS` | `:8443`, Service `netbird-reverse-proxy:8443` |
| `NB_PROXY_ACME_CERTIFICATES` | `false` |
| `NB_PROXY_CERTIFICATE_DIRECTORY` | `/certs` |
| `NB_PROXY_PROXY_PROTOCOL` | `true`, trusted from `10.42.0.0/16` |
| `NB_PROXY_HEALTH_ADDRESS` | `:8080` (`/healthz/startup`, `/healthz/ready`, `/healthz/live`) |

The token is `proxy_token` in `secrets/netbird.yaml`, minted on the server with
`netbird-server admin token create` and copied into OpenBao by
`40_openbao-config`.

## Certificates

The proxy terminates TLS itself. `/certs` is the cert-manager Certificate
`netbird-reverse-proxy-tls` for `*.luukblankenstijn.nl` and
`luukblankenstijn.nl` (ClusterIssuer `letsencrypt-dns`). ACME in the proxy is
off, so it serves only names that certificate covers.

## Exposing a service

1. Register the service in NetBird as a custom domain under
   `luukblankenstijn.nl` on the `proxy.luukblankenstijn.nl` cluster.
2. Add one `IngressRouteTCP` per host on entrypoint `websecure`, matching
   ``HostSNI(`<host>.luukblankenstijn.nl`)``, with `tls.passthrough: true`, to
   Service `netbird-reverse-proxy` port 8443.

Every exposed host is its own `HostSNI` match. Traefik evaluates TCP routers on
`websecure` before HTTP routers, so a wildcard SNI would capture every other
`*.luukblankenstijn.nl` route. No such route exists; the proxy receives no
traffic until one is added.

The proxy expects a PROXY protocol header on every connection
(`NB_PROXY_PROXY_PROTOCOL`). Traefik consumes the header frpc sends at the
`websecure` entrypoint, so the proxy only receives one if the route's Traefik
service sends a new header; nothing in `flux/` configures that.

Public clients reach the host through the edge like any other name (see
[Edge and public ingress](edge.md)); the wildcard DNS record points there.
