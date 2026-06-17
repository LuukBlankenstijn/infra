# Dashboard served by the module's built-in nginx, bound to 127.0.0.1:8080 so
# Traefik on :443 stays the only public TLS terminator.
#
# Zitadel generates the OIDC client id at runtime, but the dashboard bakes
# AUTH_CLIENT_ID into a static build at Nix eval time. We bake a sentinel
# (@@NETBIRD_CLIENT_ID@@, set in default.nix) into that build, then render the
# real value into a writable tree at runtime once tofu has delivered it.
{
  config,
  pkgs,
  cfg,
  lib,
  ...
}:
let
  htmlDir = "/var/lib/netbird-dashboard/html";
  clientIdFile = "/var/lib/netbird-oidc/dashboard-client-id";
  dashboardDrv = config.services.netbird.server.dashboard.finalDrv;
in
{
  services.netbird.server.dashboard.enableNginx = true;

  systemd.services.netbird-dashboard-render = {
    description = "Render the NetBird dashboard with the Zitadel client id";
    wantedBy = [ "multi-user.target" ];
    before = [ "nginx.service" ];
    # Hold on a fresh box until tofu/zitadel delivers the client id; the tofu
    # `systemctl restart` re-checks this once the file exists.
    unitConfig.ConditionPathExists = clientIdFile;

    path = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
    ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      StateDirectory = "netbird-dashboard";
      # nginx (separate user) must traverse + read the rendered tree.
      StateDirectoryMode = "0755";
    };

    script = ''
      set -euo pipefail
      id="$(cat ${clientIdFile})"
      rm -rf ${htmlDir}
      mkdir -p ${htmlDir}
      cp -R ${dashboardDrv}/. ${htmlDir}/
      chmod -R u+w ${htmlDir}
      grep -rl '@@NETBIRD_CLIENT_ID@@' ${htmlDir} | while read -r f; do
        sed -i "s|@@NETBIRD_CLIENT_ID@@|$id|g" "$f"
      done
      chmod -R a+rX ${htmlDir}
    '';
  };

  # Serve the runtime-rendered tree instead of the module's sentinel build.
  systemd.services.nginx.after = [ "netbird-dashboard-render.service" ];

  services.nginx.virtualHosts.${cfg.netbirdHost} = {
    root = lib.mkForce htmlDir;
    listen = [
      {
        addr = "127.0.0.1";
        port = 8080;
        ssl = false;
      }
    ];
    # SPA fallback: the dashboard is a Next.js client-side-routed app, so
    # unknown paths (/auth, /silent-auth, /peers, /add-peers, ...) must serve
    # index.html. The upstream module's default ends in =404 which breaks the
    # OIDC redirect target.
    locations."/".tryFiles = lib.mkForce "$uri $uri.html $uri/ /index.html";
  };
}
