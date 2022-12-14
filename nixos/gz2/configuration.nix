{ config, pkgs, ... }:

{
  time.timeZone = "Asia/Shanghai";

  i18n.defaultLocale = "en_US.UTF-8";

  environment.systemPackages = with pkgs; [ dig vim ];

  programs = {
    mtr.enable = true;
    fish.enable = true;
  };

  nix.settings.substituters = pkgs.lib.mkForce [
    "https://mirrors.bfsu.edu.cn/nix-channels/store"
    "https://cache.nixos.org"
  ];

  sops.secrets.tincrsa = {
    sopsFile = ./secrets.yaml;
    mode = "0600";
  };

  services.tinc.networks.kaseinet = {
    name          = "gz1";
    rsaPrivateKeyFile = "${config.sops.secrets.tincrsa.path}";
  };

  environment.etc = {
    "tinc/kaseinet/rsa_key.priv".source = "${config.sops.secrets.tincrsa.path}";
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "22.05"; # Did you read the comment?
}