{ config, lib, pkgs, modulesPath, ... }:
let
  dev_nixos = "/dev/mapper/rootblk1";
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
      luks = {
        devices = {
          rootblk0 = {
            device = "/dev/disk/by-partlabel/CRYPT_NIXOS_P1";
            allowDiscards = true;
            preLVM = true;
          };
          rootblk1 = {
            device = "/dev/disk/by-partlabel/CRYPT_NIXOS_P2";
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
    device = "/dev/disk/by-partlabel/BOOT";
    fsType = "vfat";
    neededForBoot = true;
  };

  fileSystems."/mnt/bareroot" = {
    fsType = "btrfs";
    device = dev_nixos;
    options = rootopts;
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

  fileSystems."/home/kasei" = {
    fsType = "btrfs";
    device = dev_nixos;
    options = [ "subvol=homevol_kasei" ] ++ rootopts;
    neededForBoot = true;
  };

  services.btrfs = {
    autoScrub = {
      enable = true;
      fileSystems = [ "/mnt/bareroot" ];
      interval = "monthly";
    };
  };

  swapDevices = [
    {
      device = "/dev/disk/by-partlabel/SWAP";
      discardPolicy = "once";
      randomEncryption = {
        enable = true;
      };
    }
    {
      device = "/dev/disk/by-partlabel/SWAP2";
      discardPolicy = "once";
      randomEncryption = {
        enable = true;
      };
    }
  ];
}
