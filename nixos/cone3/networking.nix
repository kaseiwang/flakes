{ config, pkgs, ... }:
let
  wanif = "ens3";
in
with pkgs.lib;
{
  sops.secrets = {
    wgkey = { };
  };
  networking = {
    hostName = "cone3";
    useDHCP = false;
    useNetworkd = true;
    tempAddresses = "disabled";

    firewall = {
      enable = true;
      allowedTCPPorts = [
        443
        9555
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
        addresses = [{ address = "66.103.210.62"; prefixLength = 24; }];
      };
      ipv6 = {
        addresses = [
          #{ address = "2607:f130:0:179::47ec:e8aa"; prefixLength = 64; }
          #{ address = "2607:f130:0:179::84dc:6698"; prefixLength = 64; }
          { address = "2607:f130:0:179::2f6b:52ea"; prefixLength = 64; }
        ];
      };
    };

    wireguard.useNetworkd = false;
    wireguard.interfaces."wg0" = {
      #table = "300";
      fwMark = "0xc8"; # 200
      listenPort = 2480;
      mtu = 1400;
      ips = [
        "10.10.0.21/32"
        "fdcd:ad38:cdc5:3:10:10:0:21"
      ];
      postSetup = ''
        tc qdisc add dev wg0 root cake bandwidth 200mbit rtt 200ms diffserv4
      '';
      privateKeyFile = "${config.sops.secrets.wgkey.path}";
      peers = [
        {
          publicKey = "1xUgYLXcalz8s224Nfn2SP8/exaL8D8cp7VWTWIp1g0=";
          allowedIPs = [
            "10.10.0.20/32"
            "fdcd:ad38:cdc5:3:10:10:0:20"
            "10.10.2.0/24"
            "fdcd:ad38:cdc5:1::/64"
            "2408:8206:18c0::/40"
            "2408:8207:18c0::/40"
          ];
        }
      ];
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
            Destination = "2408:8206:18c0::/40";
          }
          {
            Destination = "2408:8207:18c0::/40";
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
    };
  };
}
