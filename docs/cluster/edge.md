# Edge and public ingress

`home-server` takes no inbound connections from the internet. Public traffic
enters at the edge VPS and reaches Traefik through a tunnel the cluster dials
out. The edge also runs the public iroh relay that [tunnelrs](../apps/tunnelrs.md)
connects through:

```mermaid
flowchart LR
  client[Internet client] -->|80, 443/tcp| frps[frps on edge]
  frpc[frpc Deployment, namespace frpc] -->|7000/tcp, TLS + token| frps
  frps -. tunnel .-> frpc
  frpc -->|PROXY v2| traefik[Traefik 80/443]
  traefik --> apps[IngressRoutes]
  tunnelrs[tunnelrs server and connectors] -->|8443/tcp, 7842/udp| relay[iroh-relay on edge]
```

## The edge VPS

| What | Value |
| --- | --- |
| Server | Hetzner Cloud `edge`, type `cx22`, location `nbg1`, `49.12.197.36` |
| DNS | `hertzner.luukblankenstijn.nl` A record to the server, `*.luukblankenstijn.nl` CNAME to that name, both unproxied |
| OS | NixOS from `nixosConfigurations.edge` (`nix/hosts/edge`) |
| Login | user `luuk`, keys from `https://github.com/LuukBlankenstijn.keys`, passwordless sudo, no root login, no passwords; see [NixOS hosts](../hosts.md) |

`terraform/10_edge` owns the server, its Hetzner firewall and both DNS records.
`image`, `ssh_keys`, `user_data` and `public_net` are in `ignore_changes`, and
the server has `prevent_destroy`; the operating system is entirely the NixOS
configuration.

### Ports have one source

`nix/hosts/edge/ports.json` lists every open port:

| Key | Port | Used by |
| --- | --- | --- |
| `ssh` | 22/tcp | sshd |
| `frpControl` | 7000/tcp | frps control connection |
| `forwardedTcp` | 80/tcp, 443/tcp | frps public TCP listeners |
| `stun` | 3478/udp | coturn |
| `irohRelayHttps` | 8443/tcp | iroh-relay HTTPS relay |
| `irohRelayQad` | 7842/udp | iroh-relay QUIC address discovery |

The NixOS modules read it for the host firewall and the service configuration;
`terraform/10_edge/server.tf` reads it for the Hetzner firewall (plus ICMP). A
port changes in that file only.

### Services on the host

- **frps** (`frp.nix`, unit `frp-edge.service`): binds `frpControl`, token
  authentication, `transport.tls.force`, and only allows proxies on the
  `forwardedTcp` ports. The token is `frp-token` from `secrets/edge.yaml`,
  decrypted by sops-nix with the host's `/etc/ssh/ssh_host_ed25519_key` and
  passed as `FRP_TOKEN` through an environment file; a changed token restarts
  the unit.
- **coturn** (`stun.nix`): STUN only on 3478/udp; no TCP, TLS, DTLS, CLI or TURN
  relay. NetBird peers use it as `stun:hertzner.luukblankenstijn.nl:3478`.
- **iroh-relay** (`iroh-relay.nix`, unit `iroh-relay.service`): the public
  iroh relay `https://relay.luukblankenstijn.nl:8443` used by
  [tunnelrs](../apps/tunnelrs.md); see [The iroh relay](#the-iroh-relay).

### Deploying the host

comin deploys `main`; building, manual deploys and the sops recipient are on
[NixOS hosts](../hosts.md).

## The iroh relay

`iroh-relay.nix` runs `iroh-relay` from nixpkgs as the static system user
`iroh-relay`. It serves the relay over HTTPS on `irohRelayHttps` (8443/tcp,
`https://relay.luukblankenstijn.nl:8443`, relay path `/relay`, health check
`/healthz`) and QUIC address discovery on `irohRelayQad` (7842/udp). Access is
`everyone`: any iroh endpoint may relay through it. frps keeps 80 and 443; the
plain HTTP listener is bound to `127.0.0.1:3340` only.

The certificate for `relay.luukblankenstijn.nl` comes from Let's Encrypt
through `security.acme` (account `git@luukblankenstijn.nl`) with a DNS-01
challenge against Cloudflare. The token is `api_token` from
`secrets/cloudflare.yaml`, decrypted by sops-nix and passed to lego as
`CF_DNS_API_TOKEN` through an environment file. The certificate is readable by
group `iroh-relay` in `/var/lib/acme/relay.luukblankenstijn.nl/`; the relay
starts after `acme-relay.luukblankenstijn.nl.service` (which places a
self-signed certificate until the first order succeeds) and is restarted on
every renewal.

Metrics are served on `127.0.0.1:9091` and scraped by Alloy as target
`iroh-relay`.

[tunnelrs](../apps/tunnelrs.md) server and connectors use the relay, so the
cluster needs no inbound UDP.

## The tunnel

`flux/40_services/frpc` runs one `frpc` (`fatedier/frpc`) that connects to
`hertzner.luukblankenstijn.nl:7000` over TLS with the same token, read from
OpenBao `secret/frpc/frpc` through the `secret` SecretStore. It registers two
TCP proxies:

| Proxy | Type | Edge port | Target |
| --- | --- | --- | --- |
| `http` | tcp | 80 | `traefik-traefik.traefik.svc.cluster.local:80` |
| `https` | tcp | 443 | `traefik-traefik.traefik.svc.cluster.local:443` |

Both proxies prepend a PROXY protocol v2 header. `loginFailExit = false` keeps
frpc retrying while the edge is unreachable.

The Deployment has one replica and `strategy: Recreate`. frps rejects a second
client registering a proxy name that is already registered, so two frpc pods
must never overlap.

frpc reads its configuration only at startup. `frpc.toml` in the same directory
becomes the ConfigMap through a `configMapGenerator`, whose name carries a hash of
the content, so any change to the file rolls the pod.

## Secret proxies

frps also carries the [Pi tunnel](../apps/home-assistant.md#the-pi-tunnel):
`stcp` and `xtcp` proxies from `home-gateway` with visitors in namespace
`pi-tunnel`. They bind no port on the edge, so `allowPorts` and the firewall do
not change. `xtcp` uses the public STUN server `stun.easyvoip.com` for hole
punching, because frp needs RFC 5780 `OTHER-ADDRESS` and coturn on one IP has
none.

## Traefik

Traefik (`flux/20_controllers/traefik`) runs as a DaemonSet with
`externalTrafficPolicy: Local`. Entrypoints `web` and `websecure` accept PROXY
protocol from `10.42.0.0/16`, the pod CIDR frpc connects from, so applications
see the real client address. `web` redirects to `websecure`. TLS uses the default
TLSStore certificate `wildcard-luukblankenstijn-nl-tls` (`luukblankenstijn.nl`
and `*.luukblankenstijn.nl`, Let's Encrypt DNS-01 through Cloudflare, ClusterIssuer
`letsencrypt-dns`).

`mqtt.luukblankenstijn.nl` on 443 is a TCP route with TLS passthrough to mosquitto; see [Home Assistant](../apps/home-assistant.md#mosquitto).

The edge forwards only 80/tcp and 443/tcp to Traefik. Other Traefik entrypoints
(`minecraft`, `voicechat-udp`) are reachable on the node's LAN address only.
