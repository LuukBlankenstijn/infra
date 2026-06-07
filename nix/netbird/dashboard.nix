# Use the netbird-dashboard module's built-in nginx (not the broken
# static-web-server). Override the listen so nginx only binds 127.0.0.1:8080
# — Traefik on :443 stays the only public-facing TLS terminator.
{ cfg, lib, ... }:
{
  services.netbird.server.dashboard.enableNginx = true;

  services.nginx.virtualHosts.${cfg.netbirdHost} = {
    listen = [
      {
        addr = "127.0.0.1";
        port = 8080;
        ssl = false;
      }
    ];
    # SPA fallback: the dashboard is a Next.js client-side-routed app, so
    # unknown paths (/auth, /silent-auth, /peers, /add-peers, ...) must serve
    # index.html. The upstream module's default ends in =404 which breaks
    # the OIDC redirect target.
    locations."/".tryFiles = lib.mkForce "$uri $uri.html $uri/ /index.html";
  };
}
