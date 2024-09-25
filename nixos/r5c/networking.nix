{ config, pkgs, ... }:
{
  sops.secrets = {
    tinced25519 = { };
    wgcf-key = { };
  };

  services.kaseinet = {
    enable = true;
    name = "nanopir5c";
    v4addr = "10.10.0.111";
    v6addr = "fdcd:ad38:cdc5:3::111";
    ed25519PrivateKeyFile = "${config.sops.secrets.tinced25519.path}";
    extraConfig = ''
      ConnectTo = gz1
      ConnectTo = n3160
    '';
  };

  systemd.services.systemd-networkd.environment.SYSTEMD_LOG_LEVEL = "debug";
  networking = {
    hostName = "r5c";
    useDHCP = false;

    firewall = {
      enable = false;
    };

    nftables = {
      enable = true;
      flattenRulesetFile = true;
      preCheckRuleset = "sed 's/.*devices.*/devices = { lo }/g' -i ruleset.conf";
      tables = {
        mangle = {
          family = "inet";
          content = ''
            set kaseiserversv4 {
              type ipv4_addr
              flags constant, interval
              elements = {
                74.48.96.113/32, # cone
                148.135.81.252/32, # cone
                81.71.146.69/32, # gz2
              }
            }

            set kaseiserversv6 {
              type ipv6_addr
              flags constant, interval
              elements = {
                2607:f130:0:186::0/64, # cone
                2607:f130:0:17e::0/64, # cone
              }
            }

            set localnet {
              type ipv4_addr
              flags constant, interval
              elements = {
                192.168.0.0/16,
                172.16.0.0/12,
                10.0.0.0/8
              }
            }

            chain route-mark {
              ip daddr @localnet meta mark set 200
              ip daddr @kaseiserversv4 meta mark set 200
              ip6 daddr @kaseiserversv6 meta mark set 200

              meta mark 0 meta mark set 300
              meta mark 200 counter
              meta mark 300 counter
            }

            chain prerouting {
              type filter hook prerouting priority mangle + 10;
              jump route-mark
            }

            chain output {
              type route hook output priority mangle + 10; policy accept;
              jump route-mark
            }
          '';
        };
        filter = {
          family = "inet";
          content = ''
            chain input {
              type filter hook input priority filter; policy accept;

              meta l4proto {icmp, icmpv6, igmp} accept;

              ct state established,related counter accept

              tcp dport { 22, 655, 1080, 3389, 8000} accept;
              udp dport { 22, 655, 3389, 8000} accept;

              # Allow trusted networks to access the router
              iifname {
                "lan0",
                "tinc.kaseinet",
              } counter accept

              iifname "wanbr" drop
            }

            chain forward {
              type filter hook forward priority filter; policy accept;

              tcp flags syn tcp option maxseg size set rt mtu;
              iifname "wgcf" tcp flags syn tcp option maxseg size set 1360;

              # Allow trusted network WAN access
              iifname {
                      "lan0",
                      "tinc.kaseinet",
              } counter accept comment "Allow trusted LAN to WAN"

              # Allow established WAN to return
              ct state established,related counter accept;
            }

            chain output {
              type filter hook output priority 100; policy accept;
              tcp flags syn tcp option maxseg size set rt mtu;
              iifname "wgcf" tcp flags syn tcp option maxseg size set 1360;
            }
          '';
        };
        nat = {
          family = "ip";
          content = ''
            chain postrouting {
              type nat hook postrouting priority filter; policy accept;
              oifname {"wanbr", "wgcf"} masquerade
            }
          '';
        };
        nat6 = {
          family = "ip6";
          content = ''
            chain postrouting {
              type nat hook postrouting priority filter; policy accept;
              oifname {"wanbr", "wgcf"} masquerade
            }
          '';
        };
      };
    };

    useNetworkd = true;

    vlans."lan100" = {
      id = 100;
      interface = "lan0";
    };

    bridges = {
      "wanbr".interfaces = [ "wan0" "lan100" ];
    };
  };

  networking.wireguard.interfaces."wgcf" = {
    table = "300";
    fwMark = "0xc8"; # 200
    mtu = 1400;
    ips = [
      "172.16.0.2/32"
      "2606:4700:110:81d1:c1ab:267f:778c:4501/128"
    ];
    privateKeyFile = "${config.sops.secrets.wgcf-key.path}";
    peers = [
      {
        publicKey = "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=";
        endpoint = "162.159.192.1:2408"; # engage.cloudflareclient.com
        allowedIPs = [ "0.0.0.0/0" "::/0" ];
        persistentKeepalive = 60;
      }
      {
        publicKey = "1xUgYLXcalz8s224Nfn2SP8/exaL8D8cp7VWTWIp1g0=";
        endpoint = "cmcc.i.kasei.im:2480";
        allowedIPs = [ "10.10.0.20/32" "fd80:13f7::10:10:0:20/128" "2409:8a55:a00::0/40" ];
        persistentKeepalive = 60;
        dynamicEndpointRefreshSeconds = 60;
      }
    ];
    preSetup = ''
      ${pkgs.iproute}/bin/ip link set dev wan0 xdp object ${pkgs.wgcf_bpf_r5s}/wgcf_bpf section wg-cf-xdp-ingress
      ${pkgs.iproute}/bin/tc qdisc add dev wan0 clsact | true
      ${pkgs.iproute}/bin/tc filter add dev wan0 egress bpf da obj ${pkgs.wgcf_bpf_r5s}/wgcf_bpf sec wg-cf-tc-egress
    '';
    postShutdown = ''
      ${pkgs.iproute}/bin/ip link set dev wan0 xdp off
      ${pkgs.iproute}/bin/tc filter del dev wan0 egress
    '';
  };

  systemd.network = {
    links = {
      "10-wan0" = {
        matchConfig = {
          Path = "platform-3c0800000.pcie-pci-0002:01:00.0";
        };
        linkConfig = {
          Name = "wan0";
          MACAddress = "32:07:76:f4:a8:95"; # random
        };
      };
      "10-lan0" = {
        matchConfig = {
          Path = "platform-3c0400000.pcie-pci-0001:01:00.0";
        };
        linkConfig = {
          Name = "lan0";
          MACAddress = "32:07:76:f4:a8:94"; # random
        };
      };
    };
    networks = {
      "30-wanbr" = {
        matchConfig = {
          Name = "wanbr";
        };
        DHCP = "ipv4";
      };
      "40-lan0" = {
        matchConfig = {
          Name = "lan0";
        };
        address = [
          "10.10.3.1/24"
        ];
        routes = [
          { Destination = "10.10.3.0/24"; }
          { Destination = "10.10.3.0/24"; Table = "300"; }
        ];
        networkConfig = {
          DHCP = "no";
          DHCPServer = true;
          ConfigureWithoutCarrier = true;
          VLAN = [ "lan100" ];
        };
        dhcpServerConfig = {
          PoolSize = 100;
          PoolOffset = 129;
          DNS = "10.10.3.1";
          NTP = "10.10.3.1";
          Timezone = "Asia/Shanghai";
        };
        dhcpServerStaticLeases = [
          { MACAddress = "2c:f0:5d:e7:e2:a6"; Address = "10.10.3.11"; } # desktop
        ];
        routingPolicyRules = [
          {
            Family = "both";
            IncomingInterface = "wgcf";
            Table = 300;
          }
          {
            Family = "ipv4";
            FirewallMark = 300;
            Priority = 300;
            Table = 300;
          }
        ];
      };
    };
  };

  services.resolved.enable = false;

  services.chinaRoute = {
    fwmark = 200;
    enableV4 = true;
    enableV6 = true;
  };

  services.smartdns = {
    enable = true;
    settings = {
      bind = "[::]:53";
      bind-tcp = "[::]:53";
      cache-size = 262144; # 128MB
      cache-persist = false;
      resolv-hostname = true;
      prefetch-domain = false;
      log-console = true;
      log-size = "0";
      audit-enable = true;
      audit-console = true;
      audit-size = "0";
      domain-rules = [
        "/cmcc.i.kasei.im/ -no-cache -rr-ttl-max 60"
      ];
      conf-file = [
        "${pkgs.smartdns-china-list}/accelerated-domains.china.smartdns.conf"
        "${pkgs.smartdns-china-list}/apple.china.smartdns.conf"
        #"${pkgs.smartdns-china-list}/google.china.smartdns.conf"
      ];
      # smartdns does not read SAN, use CN
      server = [
        "10.224.112.2 -group china -exclude-default-group"
        "10.248.2.2 -group china -exclude-default-group"
      ];
      server-tls = [
        "1.1.1.1 -tls-host-verify cloudflare-dns.com"
        "1.0.0.1 -tls-host-verify cloudflare-dns.com"
        #"1.12.12.12 -tls-host-verify 120.53.53.53 -group china -exclude-default-group"
        #"120.53.53.53 -tls-host-verify 120.53.53.53 -group china -exclude-default-group"
        #"2400:3200:baba::1 -group netease -exclude-default-group"
        #"223.5.5.5 -tls-host-verify *.alidns.com -group china -exclude-default-group"
        #"223.6.6.6 -tls-host-verify *.alidns.com -group china -exclude-default-group"
      ];
    };
  };
}
