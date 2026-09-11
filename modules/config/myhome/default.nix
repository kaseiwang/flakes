{
  config,
  lib,
  inputs,
  pkgs,
  ...
}:
let
  cfg = config.environment.myhome;
  unfreePackages = [
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
    nixpkgs.config = lib.mkIf cfg.gui {
      allowUnfreePackages = unfreePackages;
    };

    i18n.supportedLocales = lib.mkIf cfg.gui ([ "all" ]);

    i18n.inputMethod = lib.mkIf cfg.gui {
      enable = true;
      type = "fcitx5";
      fcitx5.addons = with pkgs; [
        qt6Packages.fcitx5-chinese-addons
        fcitx5-pinyin-zhwiki
        fcitx5-pinyin-custom-pinyin-dictionary
      ];
    };

    home-manager = {
      extraSpecialArgs = { inherit inputs; };
      useGlobalPkgs = true;
      useUserPackages = true;
      sharedModules = [
        inputs.sops-nix.homeManagerModules.sops
        inputs.nix-index-database.homeModules.nix-index
      ];
      users."${cfg.username}" =
        if cfg.gui then
          {
            imports = [
              ./home-cli.nix
              ./dconf.nix
              ./home-gui.nix
            ];
          }
        else
          {
            imports = [
              ./home-cli.nix
            ];
          };
    };
  };
}
