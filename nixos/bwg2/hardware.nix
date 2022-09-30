{ config, lib, pkgs, modulesPath, ... }:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.loader = {
    grub.enable = true;
    grub.device = "/dev/sda";
    grub.version = 2;
  };

  boot.initrd.availableKernelModules = [ "ata_piix" "xhci_pci" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    fsType = "btrfs";
    device = "/dev/disk/by-uuid/f15541fc-2493-4520-9fb9-674d497ff7dc";
    options = [ "subvol=rootvol"  "noatime" "compress-force=zstd" "space_cache=v2" ];
    neededForBoot = true;
  };
  fileSystems."/boot" = {
    fsType = "btrfs";
    device = "/dev/disk/by-uuid/f15541fc-2493-4520-9fb9-674d497ff7dc";
    options = [ "subvol=boot"  "noatime" "compress-force=zstd" "space_cache=v2" ];
    neededForBoot = true;
  };
  fileSystems."/nix" = {
    fsType = "btrfs";
    device = "/dev/disk/by-uuid/f15541fc-2493-4520-9fb9-674d497ff7dc";
    options = [ "subvol=nix"  "noatime" "compress-force=zstd" "space_cache=v2" ];
    neededForBoot = true;
  };

  swapDevices = [ ];
}
