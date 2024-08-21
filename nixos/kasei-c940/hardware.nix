{ config, lib, pkgs, modulesPath, ... }:
let
  rootfs = "/dev/disk/by-uuid/56bd4f41-1270-4297-9600-e8e879d72983";
  rootopts = [
    "relatime"
    "space_cache=v2"
    "compress=zstd:1"
  ];
in
{
  hardware = {
    enableRedistributableFirmware = lib.mkDefault true;
    cpu.amd.updateMicrocode = true;
    #cpu.amd.ryzen-smu.enable = true;
    bluetooth.enable = true;
    pulseaudio.enable = false;

    graphics = {
      enable = true;
      extraPackages = [ pkgs.amdvlk ];
    };
    amdgpu = {
      initrd.enable = true;
      amdvlk = {
        enable = true;
      };
    };
  };

  # switch to power-profiles-daemon
  #powerManagement.cpuFreqGovernor = "schedutil";

  boot = {
    binfmt.emulatedSystems = [ "aarch64-linux" ];
    kernelPackages = pkgs.linuxPackages_latest;

    kernelParams = [
      "quiet"
      "vt.global_cursor_default=0"
      "mitigations=off"
      "zswap.enabled=1"
      "amd_pstate=active"
      #"lockdown=integrity"
    ];

    tmp.useTmpfs = true;

    plymouth = {
      enable = true;
    };

    lanzaboote = {
      enable = true;
      pkiBundle = "${config.users.users.kasei.home}/.local/share/secureboot";
    };

    loader = {
      timeout = 0;
      efi.canTouchEfiVariables = true;
      systemd-boot.consoleMode = "auto";
    };

    initrd = {
      systemd.enable = true;
      kernelModules = [ "btrfs" "nvme" "dm_crypt" ];
      availableKernelModules = [ "xhci_pci" "usbhid" "ahci" ];
      compressor = pkgs: "${pkgs.zstd}/bin/zstd";
      luks = {
        devices = {
          rootblk0 = {
            device = "/dev/disk/by-uuid/6499c665-5daa-4feb-94c1-be0f62e6c4f3";
            allowDiscards = true;
            preLVM = true;
          };
          rootblk1 = {
            device = "/dev/disk/by-uuid/01d91bb4-3298-4763-a99d-030a40808623";
            allowDiscards = true;
            preLVM = true;
          };
        };
      };
    };
  };

  fileSystems."/" = {
    device = "none";
    fsType = "tmpfs";
    options = [ "defaults" "size=2G" "mode=755" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/0F43-00AA";
    fsType = "vfat";
    neededForBoot = true;
  };

  fileSystems."/bareroot" = {
    fsType = "btrfs";
    device = rootfs;
    options = rootopts;
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

  fileSystems."/home/kasei" = {
    fsType = "btrfs";
    device = rootfs;
    options = [ "subvol=homevol_kasei" ] ++ rootopts;
    neededForBoot = true;
  };

  services.btrfs = {
    autoScrub = {
      enable = true;
      fileSystems = [ "/bareroot" ];
      interval = "monthly";
    };
  };

  swapDevices = [
    {
      device = "/dev/disk/by-partuuid/6f94b082-826a-48e8-8c0d-6f1b6e6eb7ba";
      discardPolicy = "once";
      randomEncryption = {
        enable = true;
      };
    }
    {
      device = "/dev/disk/by-partuuid/eb830299-33da-4c65-af32-6fd6b2dbbd20";
      discardPolicy = "once";
      randomEncryption = {
        enable = true;
      };
    }
  ];
}
