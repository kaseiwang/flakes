{ config, pkgs, ... }:

{
  environment.baseline.enable = true;
  
  time.timeZone = "Asia/Shanghai";

  i18n.defaultLocale = "en_US.UTF-8";

  environment.systemPackages = with pkgs; [ dig vim ];

  sops = {
    age = {
      keyFile = "/var/lib/sops.key";
      sshKeyPaths = [ ];
    };
    gnupg.sshKeyPaths = [ ];
  };

  nix.settings.substituters = pkgs.lib.mkForce [
    "https://mirrors.bfsu.edu.cn/nix-channels/store"
    "https://cache.nixos.org"
  ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.kasei = import ./home.nix;
  };

  programs = {
    mtr.enable = true;
    zsh.enable = true;
    dconf.enable = true;
  };

  services.xserver.enable = true;
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;


  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "22.05"; # Did you read the comment?
}