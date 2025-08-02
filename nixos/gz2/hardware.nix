{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
let
  rootfs = "/dev/disk/by-uuid/961c4e66-a37f-4441-b31f-4b4cfaa0c54e";
  rootopts = [
    "noatime"
    "compress=zstd:1"
    "space_cache=v2"
  ];
in
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.loader = {
    grub.enable = true;
    grub.device = "/dev/vda";
  };

  fileSystems = {
    "/" = {
      device = "none";
      fsType = "tmpfs";
      options = [
        "defaults"
        "size=1G"
        "mode=755"
      ];
    };
    "/boot" = {
      fsType = "btrfs";
      device = rootfs;
      options = [ "subvol=boot" ] ++ rootopts;
      neededForBoot = true;
    };
    "/nix" = {
      fsType = "btrfs";
      device = rootfs;
      options = [ "subvol=nix" ] ++ rootopts;
      neededForBoot = true;
    };
    "/persist" = {
      fsType = "btrfs";
      device = rootfs;
      options = [ "subvol=persist" ] ++ rootopts;
      neededForBoot = true;
    };
    "/mnt/bareroot" = {
      fsType = "btrfs";
      device = rootfs;
      options = rootopts;
      neededForBoot = true;
    };
  };

  swapDevices = [ ];
}
