{
  lib,
  modulesPath,
  ...
}:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  # Hetzner Cloud firmware differs by instance generation: older types boot
  # SeaBIOS, newer ones (e.g. cpx22) boot UEFI. Install grub for BOTH — to the
  # MBR (via the bios_boot partition) and to the ESP. efiInstallAsRemovable
  # writes the \EFI\BOOT\BOOTX64.EFI fallback so UEFI boots even though Hetzner
  # doesn't persist EFI NVRAM entries. disko mounts the ESP at /boot.
  # NOTE: do NOT set grub.device here — disko already populates grub.devices
  # from the disk; setting device too duplicates it (["/dev/sda","/dev/sda"]).
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

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
