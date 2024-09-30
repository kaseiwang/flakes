{ config, lib, pkgs, modulesPath, ... }:
let
  rootfs = "/dev/disk/by-uuid/33aff63a-84ba-4288-ab26-7dfc50dcdf5d";
  rootopts = [
    "noatime"
    "compress=zstd:1"
    "space_cache=v2"
  ];
in
{
  hardware = {
    enableRedistributableFirmware = lib.mkDefault true;
    cpu.intel.updateMicrocode = true;
    nvidia = {
      package = config.boot.kernelPackages.nvidiaPackages.stable;
      nvidiaSettings = false;
      open = false; # nvidia-open doesn't support GTX1060
      powerManagement = {
        enable = false; # not supported by GTX1060
      };
      dynamicBoost.enable = false; # not supported by GTX1060
      nvidiaPersistenced = true; # for power management
    };
    graphics.enable = false;
  };

  powerManagement = {
    #cpufreq.max = 2500000; # max of i5-7300HQ is 3.5GHz
    cpuFreqGovernor = "powersave";
  };

  boot = {
    loader = {
      efi.canTouchEfiVariables = true;
      systemd-boot.enable = true;
    };

    kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;
    kernelParams = [
      "mitigations=off"
    ];

    supportedFilesystems = [ "btrfs" "zfs" ];

    zfs = {
      forceImportRoot = false;
      requestEncryptionCredentials = true;
      extraPools = [ "pool0" ];
    };
  };

  fileSystems."/" = {
    device = "none";
    fsType = "tmpfs";
    options = [ "defaults" "size=2G" "mode=755" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/AE79-1C11";
    fsType = "vfat";
  };

  fileSystems."/nix" = {
    fsType = "btrfs";
    device = rootfs;
    options = [ "subvol=nixos_nix" ] ++ rootopts;
    neededForBoot = true;
  };

  fileSystems."/var/log" = {
    fsType = "btrfs";
    device = rootfs;
    options = [ "subvol=nixos_log" ] ++ rootopts;
    neededForBoot = true;
  };

  fileSystems."/persist" = {
    fsType = "btrfs";
    device = rootfs;
    options = [ "subvol=nixos_persist" ] ++ rootopts;
    neededForBoot = true;
  };

  fileSystems."/mnt/bareroot" = {
    fsType = "btrfs";
    device = rootfs;
    options = rootopts;
    neededForBoot = true;
  };

  fileSystems."/mnt/backup_disk" = {
    fsType = "btrfs";
    device = "/dev/disk/by-uuid/07a10459-a9b3-4f97-b8c4-2159e945c157";
    options = [
      "noatime"
      "compress=zstd:1"
      "space_cache=v2"
    ];
    neededForBoot = false;
  };

  swapDevices = [ ];
}
