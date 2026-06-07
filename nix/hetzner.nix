{
  lib,
  modulesPath,
  ...
}:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  # Hetzner Cloud x86 (CX/CPX) instances boot SeaBIOS, not UEFI. Install grub
  # to the MBR; the 1 MB bios_boot partition in disko.nix holds grub's
  # core.img since we use a GPT partition table. disko provides the device list.
  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = false;

  boot.kernelParams = [
    "console=tty1"
    "console=ttyS0,115200"
  ];

  networking.useNetworkd = true;
  networking.useDHCP = lib.mkForce false;
  # Hetzner Cloud doesn't expose PCI metadata that udev needs for predictable
  # names, so we get plain eth0 (sometimes en*). Match both.
  systemd.network.networks."10-wan" = {
    matchConfig.Name = "en* eth*";
    networkConfig = {
      DHCP = "ipv4";
      IPv6AcceptRA = true;
    };
    linkConfig.RequiredForOnline = "routable";
  };

  networking.nameservers = [ "1.1.1.1" "9.9.9.9" ];
  services.qemuGuest.enable = true;
}
