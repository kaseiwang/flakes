{ config, pkgs, ... }:

with pkgs.lib;

{
  networking = {
    hostName = "cone";
    useDHCP = false;
    firewall.enable = false;
    useNetworkd = true;

    defaultGateway = {
      interface = "enp0s3";
      address = "148.135.81.193";
    };
    defaultGateway6 = {
      interface = "enp0s3";
      address = "2607:f130:0:186::1";
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
        addresses = [{ address = "148.135.81.252"; prefixLength = 26; }];
      };
      ipv6 = {
        addresses = [
          { address = "2607:f130:0:186::f71a:2d6a"; prefixLength = 64; }
          { address = "2607:f130:0:186::2944:4232"; prefixLength = 64; }
          { address = "2607:f130:0:186::b1cc:1f94"; prefixLength = 64; }
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
