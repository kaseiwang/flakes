{ config, pkgs, ... }:

with pkgs.lib;

{
  # networking utils
  environment.systemPackages = with pkgs; [ mtr tcpdump socat ];

  networking = {
    hostName = "nixos-vm-cloud";
    useDHCP = false;
    firewall.enable = false;
    useNetworkd = true;
    interfaces.enp1s0 = {
      useDHCP = true;
    };
  };

  services = {
    lldpd.enable = true;
  };  
}
