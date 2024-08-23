{ config, pkgs, modulesPath, ... }:
with pkgs;
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  environment.persistence."/persist" = {
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
    ];
    directories = [
      "/var/lib"
    ];
  };

  environment.baseline.enable = true;

  system.stateVersion = pkgs.lib.mkDefault "22.05";
}
