{ config, lib, pkgs, modulesPath, ... }:

{
  hardware.enableRedistributableFirmware = lib.mkDefault true;

  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" ];
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [  ];
  boot.extraModulePackages = [ ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;

  fileSystems."/" = {
    fsType = "tmpfs";
    options = [ "defaults" "size=2G" "mode=755" ];
  };

  fileSystems."/nix" = {
    device = "/dev/disk/by-uuid/56bd4f41-1270-4297-9600-e8e879d72983";
    fsType = "btrfs";
    options = [ "subvol=nixos_nix" "relatime" "compress=zstd:1" ];
  };

  fileSystems."/persistent" = {
    device = "/dev/disk/by-uuid/56bd4f41-1270-4297-9600-e8e879d72983";
    fsType = "btrfs";
    options = [ "subvol=nixos_persistent" "relatime" "compress=zstd:1" ];
    neededForBoot = true;
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/0F43-00AA";
    fsType = "vfat";
  };
}
