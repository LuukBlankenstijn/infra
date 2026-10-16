{ ... }:
let
  ports = builtins.fromJSON (builtins.readFile ./ports.json);
in
{
  services.coturn = {
    enable = true;
    listening-port = ports.stun;
    no-tls = true;
    no-dtls = true;
    no-cli = true;
    extraConfig = ''
      stun-only
      no-tcp
    '';
  };

  networking.firewall.allowedUDPPorts = [ ports.stun ];
}
