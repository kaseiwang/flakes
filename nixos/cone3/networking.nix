{ config, pkgs, ... }:
let
  wanif = "ens3";
  warpPort = 52408;
  warpBpf = pkgs.callPackage ../../pkgs/wgcf_bpf {
    clientId = "0xd3, 0xe3, 0x35";
    localPort = warpPort;
  };
in
with pkgs.lib;
{
  sops.secrets = {
    wgcf-key = {
      owner = "systemd-network";
    };
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
      address = "163.47.135.1";
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
      mtu = 1500;
      ipv4 = {
        addresses = [
          {
            address = "163.47.135.141";
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

  # WARP's reserved bytes must be inserted on egress and cleared on ingress.
  systemd.services.wgcf-bpf = {
    description = "Cloudflare WARP reserved-byte helper";
    wantedBy = [ "multi-user.target" ];
    bindsTo = [ "sys-subsystem-net-devices-${wanif}.device" ];
    after = [
      "sys-subsystem-net-devices-${wanif}.device"
      "systemd-networkd.service"
    ];
    path = [
      pkgs.iproute2
      pkgs.jq
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      # Refuse to overwrite another service's XDP program or TC filter.
      if ip -details -json link show dev ${wanif} | jq -e '.[0] | has("xdp")' >/dev/null; then
        echo "${wanif} already has an XDP program; refusing to replace it" >&2
        exit 1
      fi
      if [ -n "$(tc filter show dev ${wanif} egress pref 2408)" ]; then
        echo "${wanif} TC priority 2408 is already in use" >&2
        exit 1
      fi
      ip link set dev ${wanif} xdpgeneric object ${warpBpf}/wgcf_bpf section wg-cf-xdp-ingress
      trap 'ip link set dev ${wanif} xdpgeneric off' ERR
      if ! tc qdisc show dev ${wanif} | grep -q 'qdisc clsact'; then
        tc qdisc add dev ${wanif} clsact
      fi
      tc filter add dev ${wanif} egress pref 2408 handle 1 bpf da obj ${warpBpf}/wgcf_bpf sec wg-cf-tc-egress
      trap - ERR
    '';
    preStop = ''
      tc filter del dev ${wanif} egress pref 2408 handle 1 bpf || true
      ip link set dev ${wanif} xdpgeneric off
    '';
  };

  systemd.network = {
    networks = {
      "75-wgcf" = {
        matchConfig.Name = "wgcf";
        linkConfig.RequiredForOnline = false;
        networkConfig = {
          DHCP = false;
          IPv6AcceptRA = false;
          LinkLocalAddressing = "no";
        };
        addresses =
          map
            (address: {
              Address = address;
              AddPrefixRoute = false;
            })
            [
              "172.16.0.2/32"
              "2606:4700:110:81d1:c1ab:267f:778c:4501/128"
            ];
        # Keep all traffic on existing routes until host routes are added manually.
      };
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
            Gateway = "163.47.135.1";
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
          { Destination = "10.10.5.0/24"; }
          { Destination = "fdcd:ad38:cdc5:5::/64"; }
          { Destination = "2408:8206::/34"; }
          { Destination = "2408:8207::/34"; }
        ];
        networkConfig = {
          DHCP = false;
        };
      };
    };

    netdevs = {
      "20-wgcf" = {
        netdevConfig = {
          Name = "wgcf";
          Kind = "wireguard";
          MTUBytes = 1400;
        };
        wireguardConfig = {
          PrivateKeyFile = config.sops.secrets.wgcf-key.path;
          ListenPort = warpPort;
          FirewallMark = 200;
          RouteTable = "off";
        };
        wireguardPeers = [
          {
            PublicKey = "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=";
            Endpoint = "162.159.192.1:2408";
            AllowedIPs = [
              "0.0.0.0/0"
              "::/0"
            ];
            PersistentKeepalive = 60;
            RouteTable = "off";
          }
        ];
      };
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
              "10.10.5.0/24"
              "fdcd:ad38:cdc5:5::/64"
              "2408:8206::/34"
              "2408:8207::/34"
            ];
          }
        ];
      };
    };
  };
}
