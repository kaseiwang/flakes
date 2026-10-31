{ pkgs, imagebuilder }:
let
  release = "25.12.6";
  profile = "xiaomi_redmi-router-ax6000-ubootmod";
  software = import ./packages.nix;
  profiles = import (imagebuilder + "/profiles.nix") { inherit pkgs release; };
  image = import (imagebuilder + "/builder.nix") (
    profiles.identifyProfile profile // software // { extraImageName = "nix-ax6000"; }
  );
  # Reuse upstream's hash-pinned downloads, dependency resolution and preparation.
  # Stop before make image: no secret or personalized firmware enters the store.
  prepared = image.overrideAttrs (_: {
    pname = "ax6000-imagebuilder-prepared";
    name = "ax6000-imagebuilder-prepared-${release}";
    phases = [
      "unpackPhase"
      "patchPhase"
      "configurePhase"
      "installPhase"
    ];
    installPhase = ''
      mkdir -p "$out"
      cp -a . "$out/"
    '';
    postInstall = "";
  });
  specification = pkgs.writeText "ax6000-specification.json" (
    builtins.toJSON {
      inherit release profile;
      inherit (software) packages disabledServices;
      target = "mediatek";
      variant = "filogic";
      templates = import ./configuration.nix;
      firstBoot = import ./first-boot.nix;
      imagebuilderRevision = imagebuilder.rev or "unknown";
    }
  );
  runtime = pkgs.writeText "build-ax6000.py" (builtins.readFile ./build.py);
in
pkgs.writeShellApplication {
  name = "build-openwrt-ax6000";
  runtimeInputs = [
    pkgs.python3
    pkgs.sops
    pkgs.gnumake
    pkgs.stdenv.cc
    pkgs.squashfsTools
    pkgs.uci
  ]
  ++ pkgs.stdenv.initialPath
  ++ image.nativeBuildInputs;
  text = ''
    exec python3 ${runtime} \
      --prepared ${prepared} \
      --specification ${specification} \
      --secrets ${./secrets.yaml} "$@"
  '';
  passthru = { inherit prepared specification; };
  meta.description = "Assemble a private AX6000 sysupgrade image outside the Nix store";
}
