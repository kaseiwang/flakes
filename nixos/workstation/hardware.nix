{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
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

    graphics = {
      enable = true;
    };

    nvidia = {
      open = true;
      modesetting.enable = true;
      powerManagement.enable = true;
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
      timeout = 5;
      systemd-boot.consoleMode = "auto";
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/efi";
      };
    };

    initrd = {
      systemd.enable = true;
      kernelModules = [
        "btrfs"
        "nvme"
        "dm_crypt"
      ];
    };

    tmp.useTmpfs = true;
  };

  disko = {
    devices = {
      disk = {
        nvme = {
          type = "disk";
          device = "/dev/disk/by-id/nvme-INTEL_SSDPEKKW010T8_PHHH845500VX1P0E";
          content = {
            type = "gpt";
            partitions = {
              esp = {
                label = "ESP";
                size = "2G";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/efi";
                  mountOptions = [ "umask=0077" ];
                };
              };
              cryptroot = {
                label = "CRYPT_NIXOS";
                size = "100%";
                content = {
                  type = "luks";
                  name = "cryptroot";
                  settings = {
                    allowDiscards = true;
                    bypassWorkqueues = true;
                    crypttabExtraOpts = [
                      "same-cpu-crypt"
                      "submit-from-crypt-cpus"
                      "fido2-device=auto"
                    ];
                  };
                  content = {
                    type = "btrfs";
                    extraArgs = [
                      "-f"
                      "--features"
                      "block-group-tree"
                    ];
                    subvolumes = {
                      "nixos_persist" = {
                        mountpoint = "/persist";
                        mountOptions = rootopts;
                      };
                      "nixos_nix" = {
                        mountpoint = "/nix";
                        mountOptions = rootopts;
                      };
                      "nixos_log" = {
                        mountpoint = "/var/log";
                        mountOptions = rootopts;
                      };
                      "homevol_kasei" = {
                        mountpoint = "/home/kasei";
                        mountOptions = rootopts;
                      };
                    };
                  };
                };
              };
            };
          };
        };
      };
      nodev = {
        "/" = {
          fsType = "tmpfs";
          mountOptions = [
            "defaults"
            "size=2G"
            "mode=755"
            "nosuid"
            "nodev"
          ];
        };
      };
    };
  };

  fileSystems."/persist".neededForBoot = true;

  services.btrfs = {
    autoScrub = {
      enable = true;
      fileSystems = [ "/mnt/bareroot" ];
      interval = "monthly";
    };
  };
}
