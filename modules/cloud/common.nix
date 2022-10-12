{ config, pkgs, modulesPath, ... }:
with pkgs;
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  sops = {
    age = {
      keyFile = "/var/lib/sops.key";
      sshKeyPaths = [ ];
    };
    gnupg.sshKeyPaths = [ ];
  };

  environment.persistence."/persist" = {
    directories = [
      "/var"
      "/home"
    ];
  };

  environment.baseline.enable = true;

  system.stateVersion = "22.05";
}
