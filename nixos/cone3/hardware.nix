{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
let
  rootopts = [
    "relatime"
    "compress-force=zstd:1"
    "space_cache=v2"
  ];
in
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot = {
    loader = {
      grub.enable = true;
    };
  };

  disko = {
    enableConfig = true;
    devices = {
      disk.vda = {
        device = "/dev/vda";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              type = "EF02";
              priority = 0;
              size = "1M";
            };
            ESP = {
              name = "ESP";
              size = "300M";
              type = "EF00";
              priority = 1;
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [
                  "fmask=0077"
                  "dmask=0077"
                ];
              };
            };
            root = {
              label = "NIXOS_ROOT";
              end = "-10M";
              priority = 2;
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ];
                subvolumes = {
                  "nix" = {
                    mountpoint = "/nix";
                    mountOptions = rootopts;
                  };
                  "persist" = {
                    mountpoint = "/persist";
                    mountOptions = rootopts;
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
            "mode=755"
          ];
        };
      };
    };
  };

  fileSystems."/persist".neededForBoot = true;

  swapDevices = [ ];
}
