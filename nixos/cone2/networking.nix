{ config, pkgs, ... }:

with pkgs.lib;
{
  networking = {
    hostName = "cone2";
    useDHCP = false;
    firewall.enable = false;
    useNetworkd = true;
    tempAddresses = "disabled";

    defaultGateway = {
      interface = "enp0s3";
      address = "74.48.96.65";
    };
    defaultGateway6 = {
      interface = "enp0s3";
      address = "2607:f130:0:17e::1";
    };

    nameservers = [
      "2606:4700:4700::1111"
      "2606:4700:4700::1001"
      "1.1.1.1"
      "1.0.0.1"
    ];

    interfaces.enp0s3 = {
      useDHCP = false;
      ipv4 = {
        addresses = [
          {
            address = "74.48.96.113";
            prefixLength = 26;
          }
        ];
      };
      ipv6 = {
        addresses = [
          {
            address = "2607:f130:0:17e::dda0:52ae";
            prefixLength = 64;
          }
          {
            address = "2607:f130:0:17e::c65b:e023";
            prefixLength = 64;
          }
          {
            address = "2607:f130:0:17e::1fd0:62b6";
            prefixLength = 64;
          }
        ];
      };
    };
  };

  systemd.network = {
    networks = {
      "40-enp0s3" = {
        matchConfig.Name = "enp0s3";
        networkConfig = {
          DHCP = "no";
          # required to use the static IP
          IPv6AcceptRA = false;
          IPv6PrivacyExtensions = pkgs.lib.mkForce false;
        };
      };
    };
  };
}
