{ config, pkgs, ... }:

{
  environment.baseline.enable = true;
  environment.myhome = {
    enable = true;
  };

  environment.systemPackages = with pkgs; [
    wol
    ethtool
    smartmontools
  ];

  nix.settings.substituters = pkgs.lib.mkForce [
    #"https://mirrors.bfsu.edu.cn/nix-channels/store"
    "https://cache.nixos.org"
  ];

  sops.defaultSopsFile = ./secrets.yaml;

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
