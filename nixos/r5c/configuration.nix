{ config, pkgs, ... }:

{
  time.timeZone = "Asia/Shanghai";

  i18n.defaultLocale = "en_US.UTF-8";

  environment.baseline.enable = true;

  environment.myhome = {
    enable = true;
    gui = false;
  };

  documentation.enable = false;
  documentation.man.enable = false;

  environment.systemPackages = with pkgs; [
    wol
    ethtool
  ];

  sops = {
    age = {
      keyFile = "/var/lib/sops.key";
      sshKeyPaths = [ ];
    };
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      wgcf-key = { };
      inadyn = {
        owner = config.users.users.inadyn.name;
        path = "/etc/inadyn.conf";
      };
    };
  };

  nix.settings.substituters = pkgs.lib.mkForce [
    #"https://mirrors.bfsu.edu.cn/nix-channels/store"
    "https://cache.nixos.org"
  ];

  # bug on first boot
  nix.gc.automatic = pkgs.lib.mkForce false;

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (pkgs.lib.getName pkg) [
    "rockchip-firmware-rk3568"
  ];

  services.openssh.settings.PasswordAuthentication = pkgs.lib.mkForce true;

  environment.etc."setupipv6.sh" = {
    mode = "0755";
    source = ./setupipv6.sh;
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?
}
