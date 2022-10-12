{ config, pkgs, ... }:

with pkgs.lib;

{
  # networking utils
  environment.systemPackages = with pkgs; [ mtr tcpdump socat ];

  networking = {
    hostName = "bwg2";
    useDHCP = false;
    firewall.enable = false;
    useNetworkd = true;
    interfaces.ens18 = {
      useDHCP = true;
    };
    interfaces.ens19 = {
      useDHCP = true;
    };
  };
}
