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
  dev_swap = "/dev/disk/by-partlabel/SWAP";
  rootopts = [
    "relatime"
    "compress-force=zstd:1"
    "space_cache=v2"
  ];
in
{
  hardware = {
    enableRedistributableFirmware = true;
    cpu.intel.updateMicrocode = true;
  };

  powerManagement.cpuFreqGovernor = "powersave";

  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    kernelParams = [
      "mitigations=off"
      "consoleblank=120"
      "libata.force=1.00:nodmalog" # fix "ata1.00: qc timeout after 15000 msecs"
    ];
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    kernel.sysctl = {
      "net.ipv4.conf.all.forwarding" = true;
      "net.ipv6.conf.all.forwarding" = true;
      "net.ipv4.conf.default.forwarding" = true;
      "net.ipv6.conf.default.forwarding" = true;
      "net.core.rps_default_mask" = "f";
      "net.core.rps_sock_flow_entries" = 32768;
      "net.netfilter.nf_conntrack_max" = 1048576;
    };

    tmp.useTmpfs = true;
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
    neededForBoot = true;
  };
  fileSystems."/nix" = {
    fsType = "btrfs";
    device = dev_nixos;
    options = [ "subvol=nixos_nix" ] ++ rootopts;
    neededForBoot = true;
  };
  fileSystems."/persist" = {
    fsType = "btrfs";
    device = dev_nixos;
    options = [ "subvol=nixos_persist" ] ++ rootopts;
    neededForBoot = true;
  };

  fileSystems."/var/log" = {
    fsType = "btrfs";
    device = dev_nixos;
    options = [ "subvol=nixos_log" ] ++ rootopts;
    neededForBoot = true;
  };

  fileSystems."/mnt/bareroot" = {
    fsType = "btrfs";
    device = dev_nixos;
    options = rootopts;
    neededForBoot = true;
  };

  swapDevices = [ ];
}
