{ config, pkgs, ... }:

with pkgs.lib;

{
  # networking utils
  environment.systemPackages = with pkgs; [ mtr tcpdump socat ];

  networking = {
    hostName = "kasei-c940";
    useDHCP = false;
    firewall.enable = false;
    useNetworkd = true;
  };

  services = {
    lldpd.enable = true;
  };
}
