{ config, pkgs, lib, inputs, ... }:
let
  cfg = config.environment.baseline;
in
with lib;
{
  options.environment.baseline = {
    enable = mkEnableOption "baseline configurations";
  };
  config = lib.mkIf cfg.enable {
    time.timeZone = "Asia/Shanghai";

    networking.domain = "i.kasei.im";

    users.users.kasei = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      shell = pkgs.fish;
      hashedPassword = "$y$j9T$Cztrc67arZlblPKugSBdQ/$pIewNcmPmTwDhTadxYPeNCnZwstoJbzCgfgBN4tRDe9";
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDj511blib/6tA4k8NfMQCgjVulmXKJPzSIfqu7Aq003"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC8RaXk0ij4Nc5nHoJ0sqVaMp6xNwhx4qPs6Rl+9qi+p"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIZVR8WmjDHF/Z1NU77PgOWb/I6aDo2ZZA40N24y5Si8"
      ];
    };

    users.users.root = {
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDj511blib/6tA4k8NfMQCgjVulmXKJPzSIfqu7Aq003"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC8RaXk0ij4Nc5nHoJ0sqVaMp6xNwhx4qPs6Rl+9qi+p"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIZVR8WmjDHF/Z1NU77PgOWb/I6aDo2ZZA40N24y5Si8"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGYS314z/+xrO5qjNWmTDLPo9OSk+mHQYPz8J0WOYbbQ"
        "ecdsa-sha2-nistp521 AAAAE2VjZHNhLXNoYTItbmlzdHA1MjEAAAAIbmlzdHA1MjEAAACFBAB5TdMiOGcOgZXw4i2m3yqjCBcz5Nwk3E/LsQ7L2nYG+3ze/jineg96afDjNM6Rds4ScddyyQIt1kQPidfwK+n6+wA4wR7sPc8pCXkNcPYOlJgm174DS87g8px2ouNUp4HX8Gzm7zYAj+mfoUlCCZukPecHhch0J0ym0rVXFaiDnnNROA=="
      ];
    };

    sops = {
      age = {
        keyFile = "/var/lib/sops.key";
      };
    };

    nix = {
      package = pkgs.nixVersions.stable;
      settings = {
        auto-optimise-store = true;
        auto-allocate-uids = true;
        use-cgroups = true;
        trusted-users = [ "kasei" ];
        experimental-features = [ "nix-command" "flakes" "auto-allocate-uids" "cgroups" ];
      };
      channel.enable = false;
      gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 7d";
      };
    };

    boot = {
      kernel.sysctl = {
        #"net.core.default_qdisc" = "fq_codel";
        "net.core.default_qdisc" = "cake";
        "net.ipv4.tcp_congestion_control" = "bbr";
        # bigger buffer for quic connection
        "net.core.rmem_max" = 8192000;
        "net.core.wmem_max" = 8192000;
      };
    };

    environment = {
      systemPackages = with pkgs; [
        bpftrace
        btop
        curl
        dig
        file
        gdu
        inetutils
        mtr
        pciutils
        socat
        sysstat
        tcpdump
        usbutils
      ];
      pathsToLink = [ "/share/fish" ];
    };

    security = {
      sudo-rs = {
        enable = true;
      };
      # I want to use the ECDSA Root
      acme.defaults = {
        extraLegoRunFlags = [ "--preferred-chain=ISRG Root X2" ];
        extraLegoRenewFlags = [ "--preferred-chain=ISRG Root X2" ];
      };
    };

    systemd.network.enable = true;

    # https://github.com/NixOS/nixpkgs/commit/8f4b41cfd44275f3905829d46c7a158689b47e10
    boot.initrd.systemd.suppressedUnits = [ "systemd-machine-id-commit.service" ];
    systemd.suppressedSystemUnits = [ "systemd-machine-id-commit.service" ];

    programs = {
      neovim = {
        enable = true;
        defaultEditor = true;
        viAlias = true;
        vimAlias = true;
      };
      fish.enable = true;
      iftop.enable = true;
      iotop.enable = true;
    };

    services = {
      fstrim.enable = true;
      irqbalance.enable = true;
      vnstat.enable = true;

      openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = false;
          Ciphers = [
            "aes256-gcm@openssh.com"
            "aes128-gcm@openssh.com"
            "chacha20-poly1305@openssh.com"
          ];
        };
        # disable rsa
        hostKeys = [
          {
            path = "/etc/ssh/ssh_host_ed25519_key";
            type = "ed25519";
          }
        ];
      };
    };

    documentation.nixos.enable = false;
  };
}
