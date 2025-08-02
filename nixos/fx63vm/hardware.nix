{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
let
  dev_boot = "/dev/disk/by-partlabel/BOOT";
  dev_nixos = "/dev/disk/by-partlabel/NIXOS";
  rootopts = [
    "noatime"
    "compress-force=zstd:1"
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

    kernelParams = [
      "mitigations=off"
      "zfs.zfs_arc_min=6442450944" # 6GB
      "zfs.zfs_arc_max=10737418240" # 10GB
    ];

    supportedFilesystems = [
      "btrfs"
      "zfs"
    ];

    zfs = {
      forceImportRoot = false;
      requestEncryptionCredentials = true;
      extraPools = [ "pool0" ];
    };
  };

  fileSystems."/" = {
    device = "none";
    fsType = "tmpfs";
    options = [
      "defaults"
      "size=2G"
      "mode=755"
    ];
  };

  fileSystems."/boot" = {
    device = dev_boot;
    fsType = "vfat";
  };

  fileSystems."/nix" = {
    fsType = "btrfs";
    device = dev_nixos;
    options = [ "subvol=nixos_nix" ] ++ rootopts;
    neededForBoot = true;
  };

  fileSystems."/var/log" = {
    fsType = "btrfs";
    device = dev_nixos;
    options = [ "subvol=nixos_log" ] ++ rootopts;
    neededForBoot = true;
  };

  fileSystems."/persist" = {
    fsType = "btrfs";
    device = dev_nixos;
    options = [ "subvol=nixos_persist" ] ++ rootopts;
    neededForBoot = true;
  };

  fileSystems."/mnt/bareroot" = {
    fsType = "btrfs";
    device = dev_nixos;
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

  swapDevices = [
  ];
}
