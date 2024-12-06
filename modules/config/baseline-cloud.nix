{ config, pkgs, lib, modulesPath, inputs, ... }:
let
  cfg = config.environment.baseline_cloud;
in
with lib;
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  options.environment.baseline_cloud = {
    enable = mkEnableOption "baseline configurations for vps";
  };
  config = lib.mkIf cfg.enable {
    environment.persistence."/persist" = {
      files = [
        "/etc/machine-id"
        "/etc/ssh/ssh_host_ed25519_key"
        "/etc/ssh/ssh_host_ed25519_key.pub"
      ];
      directories = [
        "/var/lib"
        "/var/backup"
      ];
    };

    environment.baseline.enable = true;

    environment.myhome = {
      enable = true;
    };

    system.stateVersion = pkgs.lib.mkDefault "22.05";
  };
}
