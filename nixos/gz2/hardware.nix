{ config, lib, pkgs, modulesPath, ... }:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.loader = {
    grub.enable = true;
    grub.device = "/dev/vda";
  };

  boot.initrd.availableKernelModules = [ "ata_piix" "xhci_pci" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    fsType = "btrfs";
    device = "/dev/disk/by-uuid/961c4e66-a37f-4441-b31f-4b4cfaa0c54e";
    options = [ "subvol=rootvol" "noatime" "compress-force=zstd:1" "space_cache=v2" ];
    neededForBoot = true;
  };
  fileSystems."/boot" = {
    fsType = "btrfs";
    device = "/dev/disk/by-uuid/961c4e66-a37f-4441-b31f-4b4cfaa0c54e";
    options = [ "subvol=boot" "noatime" "compress-force=zstd:1" "space_cache=v2" ];
    neededForBoot = true;
  };
  fileSystems."/nix" = {
    fsType = "btrfs";
    device = "/dev/disk/by-uuid/961c4e66-a37f-4441-b31f-4b4cfaa0c54e";
    options = [ "subvol=nix" "noatime" "compress-force=zstd:1" "space_cache=v2" ];
    neededForBoot = true;
  };
  fileSystems."/persist" = {
    fsType = "btrfs";
    device = "/dev/disk/by-uuid/961c4e66-a37f-4441-b31f-4b4cfaa0c54e";
    options = [ "subvol=persist" "noatime" "compress-force=zstd:1" "space_cache=v2" ];
    neededForBoot = true;
  };

  swapDevices = [ ];
}
