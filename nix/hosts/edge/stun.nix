{ config, ... }:
{
  services.coturn = {
    enable = true;
    listening-port = 3478;
    no-tls = true;
    no-dtls = true;
    no-cli = true;
    extraConfig = ''
      stun-only
      no-tcp
    '';
  };

  networking.firewall.allowedUDPPorts = [ config.services.coturn.listening-port ];
}
