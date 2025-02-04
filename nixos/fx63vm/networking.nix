{ config, pkgs, ... }:

{
  systemd.services.systemd-networkd.environment.SYSTEMD_LOG_LEVEL = "debug";
  networking = {
    hostName = "nas0";
    hostId = pkgs.lib.concatStringsSep "" (pkgs.lib.take 8
      (pkgs.lib.stringToCharacters
        (builtins.hashString "sha256" config.networking.hostName)));

    useDHCP = true;
    useNetworkd = true;

    wireless = {
      enable = true;
      secretsFile = "${config.sops.secrets.wireless.path}";
      networks = {
        kaseinet.pskRaw = "ext:psk_kaseinet";
      };
    };

    interfaces."enp2s0" = {
      useDHCP = true;
    };

    nftables = {
      enable = true;
    };

    firewall = {
      enable = true;
      allowedTCPPorts = [
        443 # https
        5357 # samba-wsdd
        6771 # bittorrent
        12526 # bittorrent
        57299 # bittorrent
      ];
      allowedUDPPorts = [
        443
        1900
        3702 # samba-wsdd
        6771 # bittorrent
        12526 # bittorrent
        57299 # bittorrent
      ];
      extraInputRules = ''ip saddr { 10.0.0.0/8 } tcp dport 3260 accept'';
    };
  };
}
