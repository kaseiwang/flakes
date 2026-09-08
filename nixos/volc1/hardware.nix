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
      systemd-boot.enable = true;
    };
  };

  disko = {
    enableConfig = true;
    imageBuilder.pkgs = pkgs // {
      vmTools = pkgs.vmTools.override {
        # Disko's aggregateModules tree contains the image but has no target attribute.
        kernelImage = config.disko.imageBuilder.kernelPackages.kernel.target;
      };
    };
    devices = {
      disk.vda = {
        device = "/dev/vda";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
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
              size = "100%";
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
