{ config, lib, pkgs, modulesPath, ... }:
let
  rootfs = "/dev/disk/by-uuid/59afa43f-10a6-44dd-ab95-37c469eafc39";
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
    kernelModules = [ "kvm-intel" ];
    kernelParams = [
      "mitigations=off"
      "consoleblank=120"
      "libata.force=1.00:nodmalog" # fix "ata1.00: qc timeout after 15000 msecs"
    ];
    extraModulePackages = [ ];
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    initrd = {
      kernelModules = [ ];
      availableKernelModules = [ "ahci" "xhci_pci" "usbhid" "sd_mod" ];
    };
    kernel.sysctl = {
      "net.ipv4.conf.all.forwarding" = true;
      "net.ipv6.conf.all.forwarding" = true;
      "net.ipv4.conf.default.forwarding" = true;
      "net.ipv6.conf.default.forwarding" = true;
    };

    tmp.useTmpfs = true;
  };

  fileSystems."/" = {
    device = "none";
    fsType = "tmpfs";
    options = [ "defaults" "size=2G" "mode=755" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/EDE1-C2A1";
    fsType = "vfat";
    neededForBoot = true;
  };
  fileSystems."/nix" = {
    fsType = "btrfs";
    device = rootfs;
    options = [ "subvol=nixos_nix" ] ++ rootopts;
    neededForBoot = true;
  };
  fileSystems."/persist" = {
    fsType = "btrfs";
    device = rootfs;
    options = [ "subvol=nixos_persist" ] ++ rootopts;
    neededForBoot = true;
  };

  fileSystems."/var/log" = {
    fsType = "btrfs";
    device = rootfs;
    options = [ "subvol=nixos_log" ] ++ rootopts;
    neededForBoot = true;
  };

  fileSystems."/mnt/bareroot" = {
    fsType = "btrfs";
    device = rootfs;
    options = rootopts;
    neededForBoot = true;
  };

  swapDevices = [ ];
}
