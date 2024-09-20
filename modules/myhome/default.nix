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
    nixpkgs.config.allowUnfreePredicate = lib.mkIf cfg.gui unfreepkgs;

    fonts = {
      enableDefaultPackages = false;
      packages = with pkgs; [
        noto-fonts
        noto-fonts-cjk-sans
        noto-fonts-cjk-serif
        noto-fonts-emoji
        wqy_microhei
        jetbrains-mono
        (nerdfonts.override { fonts = [ "JetBrainsMono" "Noto" ]; })
      ];
      fontDir.enable = true;
      fontconfig = {
        defaultFonts = pkgs.lib.mkForce {
          serif = [ "Noto Serif CJK SC" "Noto Serif" ];
          sansSerif = [ "Noto Sans CJK SC" "Noto Sans" ];
          monospace = [ "Noto Sans Mono" "Noto Sans Mono CJK SC" ];
          emoji = [ "Noto Color Emoji" ];
        };
        subpixel = {
          rgba = "rgb";
          lcdfilter = "default";
        };
      };
    };

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
