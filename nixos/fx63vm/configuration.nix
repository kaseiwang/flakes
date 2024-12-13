{ config, pkgs, ... }:

{
  environment.baseline.enable = true;

  environment.myhome = {
    enable = true;
  };

  boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = true;
  };

  sops.defaultSopsFile = ./secrets.yaml;
  sops.secrets = {
    acme-cloudflare = {
      owner = config.users.users."acme".name;
    };
  };

  virtualisation.containers = {
    storage.settings = {
      storage = {
        driver = "btrfs";
        graphroot = "/var/lib/containers/storage";
        runroot = "/run/containers/storage";
      };
    };
  };

  systemd = {
    enableEmergencyMode = false;
    sleep.extraConfig = ''
      AllowSuspend=no
      AllowHibernation=no
    '';
  };

  services.logind = {
    lidSwitch = "ignore";
    lidSwitchExternalPower = "ignore";
  };

  environment.systemPackages = with pkgs; [
    config.boot.kernelPackages.cpupower
    smartmontools
    rclone
  ];

  programs.fuse.userAllowOther = true;

  services.xserver.videoDrivers = [ "nvidia" ];

  security.acme = {
    acceptTerms = true;
    defaults = {
      server = "https://acme-v02.api.letsencrypt.org/directory";
      email = "kasei@kasei.im";
      dnsProvider = "cloudflare";
      dnsResolver = "119.29.29.29:53";
      credentialsFile = "${config.sops.secrets.acme-cloudflare.path}";
      reloadServices = [ "nginx" ];
    };
    certs = {
      "kasei.im" = {
        domain = "kasei.im";
        extraDomainNames = [ "*.kasei.im" "*.i.kasei.im" ];
        keyType = "ec256";
      };
    };
  };

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (pkgs.lib.getName pkg) [
    "nvidia-x11"
    "nvidia-persistenced"
    "libXNVCtrl"
  ];

  users = {
    users = {
      kasei.extraGroups = [ "qbittorrent" ];
      nginx.extraGroups = [ "acme" "grafana" ];
      nextcloud.extraGroups = [ "redis-nextcloud" ];
    };
    groups."nas" = {
      members = [ "kasei" "qbittorrent" "nextcloud" ];
    };
  };

  nix.settings.substituters = pkgs.lib.mkForce [
    #"https://mirrors.bfsu.edu.cn/nix-channels/store"
    "https://cache.nixos.org"
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

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "22.05"; # Did you read the comment?
}
