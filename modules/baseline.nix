{ config, pkgs, lib, ... }:
let
  cfg = config.environment.baseline;
in
with lib;
{
  options.environment.baseline = {
    enable = mkEnableOption "baseline configurations";
  };
  config = lib.mkIf cfg.enable {
    networking.domain = "i.kasei.im";
    users.users.kasei = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      shell = pkgs.fish;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDj511blib/6tA4k8NfMQCgjVulmXKJPzSIfqu7Aq003"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC8RaXk0ij4Nc5nHoJ0sqVaMp6xNwhx4qPs6Rl+9qi+p"
      ];
    };

    users.users.root = {
      openssh.authorizedKeys.keys = [
        "ecdsa-sha2-nistp521 AAAAE2VjZHNhLXNoYTItbmlzdHA1MjEAAAAIbmlzdHA1MjEAAACFBAB5TdMiOGcOgZXw4i2m3yqjCBcz5Nwk3E/LsQ7L2nYG+3ze/jineg96afDjNM6Rds4ScddyyQIt1kQPidfwK+n6+wA4wR7sPc8pCXkNcPYOlJgm174DS87g8px2ouNUp4HX8Gzm7zYAj+mfoUlCCZukPecHhch0J0ym0rVXFaiDnnNROA== kasei@kasei.im"
      ];
    };

    services.openssh = {
      enable = true;
    };

    services.vnstat = {
      enable = true;
    };

    nix = {
      package = pkgs.nixVersions.stable;
      settings = {
        auto-optimise-store = true;
        experimental-features = [ "nix-command" "flakes" ];
        allowed-uris = [ "https://github.com" ];
      };
      gc = {
        automatic = true;
        dates = "daily";
        options = "--delete-older-than 7d";
      };
    };

    boot = {
      kernel.sysctl = {
        "net.core.default_qdisc" = "fq_codel";
        "net.ipv4.tcp_congestion_control" = "bbr";
      };
    };

    environment = {
      systemPackages = with pkgs; [
        vim curl tmux htop
        git neovim ncdu iftop iotop file
        direnv nix-direnv
      ];
      interactiveShellInit = ''
        eval "$(direnv hook bash)"
      '';
      variables.EDITOR = "vim";
      pathsToLink = [ "/share/nix-direnv" ];
    };

    systemd.network.enable = true;

    programs = {
      mosh = {
        enable = true;
      };
      neovim = {
        enable = true;
        vimAlias = true;
      };
    };

    documentation.nixos.enable = false;
  };
}