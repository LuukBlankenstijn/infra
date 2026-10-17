{ lib, ... }:
{
  boot.initrd.availableKernelModules = [
    "pcie_brcmstb"
    "reset-raspberrypi"
    "usbhid"
    "uas"
    "usb_storage"
    "vc4"
  ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
  };

  swapDevices = [ ];

  hardware.enableRedistributableFirmware = true;

  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}
