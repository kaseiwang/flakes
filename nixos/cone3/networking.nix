{ config, pkgs, ... }:

with pkgs.lib;
{
  networking = {
    hostName = "cone3";
    useDHCP = false;
    firewall.enable = false;
    useNetworkd = true;
    tempAddresses = "disabled";

    defaultGateway = {
      interface = "enp0s3";
      address = "66.103.210.1";
    };
    defaultGateway6 = {
      interface = "enp0s3";
      address = "2607:f130:0:179::1";
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
        addresses = [{ address = "66.103.210.62"; prefixLength = 24; }];
      };
      ipv6 = {
        addresses = [
          { address = "2607:f130:0:179::47ec:e8aa"; prefixLength = 64; }
          { address = "2607:f130:0:179::84dc:6698"; prefixLength = 64; }
          { address = "2607:f130:0:179::2f6b:52ea"; prefixLength = 64; }
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
