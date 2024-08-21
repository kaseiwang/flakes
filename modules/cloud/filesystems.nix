{ ... }:
let
  device = "/dev/disk/by-partlabel/NIXOS";
  fsType = "btrfs";
  options = [ "noatime" "compress-force=zstd:1" "space_cache=v2" ];
in
{
  fileSystems = {
    "/" = {
      inherit device fsType;
      options = [ "subvol=rootvol" ] ++ options;
    };

    "/boot" = {
      inherit device fsType;
      options = [ "subvol=boot" ] ++ options;
    };

    "/nix" = {
      inherit device fsType;
      options = [ "subvol=nix" ] ++ options;
    };

    "/var/log" = {
      inherit device fsType;
      options = [ "subvol=log" ] ++ options;
    };

    "/persist" = {
      inherit device fsType;
      options = [ "subvol=persist" ] ++ options;
      neededForBoot = true;
    };
  };
}
