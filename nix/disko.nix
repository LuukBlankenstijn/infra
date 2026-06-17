{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/sda";
    content = {
      type = "gpt";
      partitions = {
        # Dual-boot layout: a BIOS boot partition (older SeaBIOS instance types)
        # AND an ESP (newer UEFI instance types, e.g. cpx22). grub installs to
        # both so the box boots regardless of which firmware Hetzner hands it.
        bios_boot = {
          size = "1M";
          type = "EF02"; # BIOS boot partition for grub on GPT
          priority = 0;  # first on disk
        };
        ESP = {
          size = "512M";
          type = "EF00"; # EFI system partition
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
            mountOptions = [ "noatime" ];
          };
        };
      };
    };
  };
}
