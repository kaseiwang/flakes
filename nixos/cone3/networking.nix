{ config, pkgs, ... }:
let
  wanif = "ens3";
in
with pkgs.lib;
{
  sops.secrets = {
    wgkey = {
      owner = "systemd-network";
    };
  };
  networking = {
    hostName = "cone3";
    useDHCP = false;
    useNetworkd = true;
    tempAddresses = "disabled";

    firewall = {
      enable = true;
      trustedInterfaces = [ "wg0" ];
      allowedTCPPorts = [
        443
        8688
      ];
      allowedUDPPorts = [
        2480
      ];
    };

    defaultGateway = {
      interface = "${wanif}";
      address = "66.103.210.1";
    };
    defaultGateway6 = {
      interface = "${wanif}";
      address = "2607:f130:0:179::1";
    };

    nat = {
      enable = true;
      enableIPv6 = true;
      externalInterface = "${wanif}";
      internalInterfaces = [ "wg0" ];
    };

    nameservers = [
      "2606:4700:4700::1111"
      "2606:4700:4700::1001"
      "1.1.1.1"
      "1.0.0.1"
    ];

    interfaces."${wanif}" = {
      useDHCP = false;
      ipv4 = {
        addresses = [
          {
            address = "66.103.210.62";
            prefixLength = 24;
          }
        ];
      };
      ipv6 = {
        addresses = [
          #{ address = "2607:f130:0:179::47ec:e8aa"; prefixLength = 64; }
          #{ address = "2607:f130:0:179::84dc:6698"; prefixLength = 64; }
          {
            address = "2607:f130:0:179::2f6b:52ea";
            prefixLength = 64;
          }
        ];
      };
    };
  };

  systemd.network = {
    networks = {
      "40-${wanif}" = {
        matchConfig.Name = "${wanif}";
        networkConfig = {
          DHCP = "no";
          # required to use the static IP
          IPv6AcceptRA = false;
          IPv6PrivacyExtensions = pkgs.lib.mkForce false;
        };
        routes = [
          {
            Gateway = "66.103.210.1";
            Table = 200;
          }
          {
            Gateway = "2607:f130:0:179::1";
            Table = 200;
          }
          # allow both wan and wg
          {
            Destination = "2408:8206::/34";
            Metric = 2048;
          }
          {
            Destination = "2408:8207::/34";
            Metric = 2048;
          }
        ];

        routingPolicyRules = [
          {
            Family = "both";
            FirewallMark = 200;
            Priority = 200;
            Table = 200;
          }
        ];
      };
      "75-wg0" = {
        matchConfig = {
          Name = "wg0";
        };
        address = [
          "10.10.0.21/32"
          "fdcd:ad38:cdc5:3:10:10:0:21"
        ];
        routes = [
          { Destination = "10.10.0.20/32"; }
          { Destination = "fdcd:ad38:cdc5:3:10:10:0:20"; }
          { Destination = "10.10.2.0/24"; }
          { Destination = "fdcd:ad38:cdc5:1::/64"; }
          { Destination = "2408:8206::/34"; }
          { Destination = "2408:8207::/34"; }
        ];
        networkConfig = {
          DHCP = false;
        };
      };
    };

    netdevs = {
      "20-wg0" = {
        netdevConfig = {
          Name = "wg0";
          Kind = "wireguard";
          MTUBytes = 1408; # round down to 16bytes
        };
        wireguardConfig = {
          ListenPort = 2480;
          FirewallMark = 200; # go underlay
          PrivateKeyFile = "${config.sops.secrets.wgkey.path}";
        };
        wireguardPeers = [
          {
            PublicKey = "1xUgYLXcalz8s224Nfn2SP8/exaL8D8cp7VWTWIp1g0=";
            AllowedIPs = [
              "10.10.0.20/32"
              "fdcd:ad38:cdc5:3:10:10:0:20"
              "10.10.2.0/24"
              "fdcd:ad38:cdc5:1::/64"
              "2408:8206::/34"
              "2408:8207::/34"
            ];
          }
        ];
      };
    };
  };
}
