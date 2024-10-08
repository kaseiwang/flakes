{ config, pkgs, lib, inputs, ... }:
let
  cfg = config.environment.myhome;
  unfreepkgs = pkg: builtins.elem (pkgs.lib.getName pkg) [
    "feishu"
    "code"
    "vscode"
    "vscode-extension-ms-vscode-remote-remote-ssh"
    "vscode-extension-github-copilot"
    "vscode-extension-github-copilot-chat"
    "vscode-extension-signageos-signageos-vscode-sops"
  ];
in
with lib;
{
  options.environment.myhome = {
    enable = mkEnableOption "myhome configurations";
    gui = mkEnableOption {
      default = false;
      description = "enable GUI";
    };
    username = mkOption {
      type = types.str;
      default = "kasei";
      description = "username";
    };
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.config.allowUnfreePredicate = lib.mkIf cfg.gui (lib.mkAfter unfreepkgs);

    i18n.supportedLocales =  lib.mkIf cfg.gui ([ "all" ]);

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      sharedModules = [
        inputs.sops-nix.homeManagerModules.sops
        inputs.nix-index-database.hmModules.nix-index
      ];
      users."${cfg.username}" =
        if cfg.gui then {
          imports = [
            ./home-cli.nix
            ./dconf.nix
            ./home-gui.nix
          ];
        } else {
          imports = [
            ./home-cli.nix
          ];
        };
    };
  };
}
