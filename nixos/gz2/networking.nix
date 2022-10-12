{ config, pkgs, ... }:

with pkgs.lib;

{
  # networking utils
  environment.systemPackages = with pkgs; [ mtr tcpdump socat ];

  networking = {
    hostName = "gz2";
    useDHCP = false;
    firewall.enable = false;
    useNetworkd = true;
    interfaces.ens5 = {
      useDHCP = true;
    };
  };
}
