{ config, pkgs, ... }:

with pkgs.lib;

{
  networking = {
    hostName = "gz2";
    useDHCP = false;
    firewall.enable = false;
    useNetworkd = true;
    interfaces.ens5 = {
      useDHCP = true;
    };
    interfaces."tinc.kaseinet" = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "10.10.0.11";
          prefixLength = 32;
        }
      ];
      ipv4.routes = [
        {
          address = "10.10.0.0";
          prefixLength = 24;
          options = {
            Metric = "500";
          };
        }
        {
          address = "10.10.2.0";
          prefixLength = 24;
          options = {
            Metric = "500";
          };
        }
        {
          address = "10.10.3.0";
          prefixLength = 24;
          options = {
            Metric = "500";
          };
        }
      ];
    };
  };
}
