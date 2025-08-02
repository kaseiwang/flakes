{
  config,
  pkgs,
  lib,
  modulesPath,
  inputs,
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
  config = {
    fileSystems = lib.mkForce {
      "/" = {
        fsType = "ext4";
        options = [
          "relatime"
          "data=writeback"
        ];
        label = "NIXOS";
      };
    };
    # Builds an (opinionated) rootfs image.
    # NOTE: *only* the rootfs.
    #       it is expected the end-user will assemble the image as they need.
    system.build.rootfsImage =
      pkgs.callPackage
        (
          {
            callPackage,
            lib,
            populateCommands,
          }:
          callPackage "${inputs.nixpkgs}/nixos/lib/make-ext4-fs.nix" ({
            storePaths = config.system.build.toplevel;
            compressImage = false;
            populateImageCommands = populateCommands;
            volumeLabel = config.fileSystems."/".label;
          })
        )
        {
          populateCommands = ''
            mkdir -p ./files/boot
            ${config.boot.loader.generic-extlinux-compatible.populateCmd} -c ${config.system.build.toplevel} -d ./files/boot
          '';
        };
  };
}
