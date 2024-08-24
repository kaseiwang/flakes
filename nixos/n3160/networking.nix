{ config, pkgs, ... }:

with pkgs.lib;
let
  # for dynamic dns
  directdns = pkgs.writeText "direct.conf" ''
    nameserver /api.cloudflare.com/china
    nameserver /dns64.cloudflare-dns.com/china
    address /*hanime.tv/172.19.0.2
    address /*hanime.tv/fdf0:dcba:9876::2
    address /*docker.io/172.19.0.2
    address /*docker.io/fdf0:dcba:9876::2
    address /*docker.com/172.19.0.2
    address /*docker.com/fdf0:dcba:9876::2
  '';

  wanif = "ppp0";
  lanif = "ens1";
in
{
  sops.secrets = {
    wireguard-key = { };
    wg-office-key = { };
    ddns-token = { };
    singboxpass = { };
    ppp0-config = {
      path = "/etc/ppp/peers/ppp0";
      mode = "600";
    };
    ddns = { };
  };

  systemd.services."pppd-ppp0" =
    let
      name = "ppp0";
    in
    {
      before = [ "network.target" ];
      wants = [ "network.target" ];
      after = [ "network-pre.target" "sops-nix.service" ];
      environment = {
        # pppd likes to write directly into /var/run. This is rude
        # on a modern system, so we use libredirect to transparently
        # move those files into /run/pppd.
        LD_PRELOAD = "${pkgs.libredirect}/lib/libredirect.so";
        NIX_REDIRECTS = "/var/run=/run/pppd";
      };
      serviceConfig =
        let
          capabilities = [
            "CAP_BPF"
            "CAP_SYS_TTY_CONFIG"
            "CAP_NET_ADMIN"
            "CAP_NET_RAW"
          ];
        in
        {
          ExecStart = "${pkgs.ppp}/sbin/pppd call ${name} nodetach nolog";
          Restart = "always";
          RestartSec = 5;

          AmbientCapabilities = capabilities;
          CapabilityBoundingSet = capabilities;
          KeyringMode = "private";
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
          NoNewPrivileges = true;
          PrivateMounts = true;
          PrivateTmp = true;
          ProtectControlGroups = true;
          ProtectHome = true;
          ProtectHostname = true;
          ProtectKernelModules = true;
          # pppd can be configured to tweak kernel settings.
          ProtectKernelTunables = false;
          ProtectSystem = "strict";
          RemoveIPC = true;
          RestrictAddressFamilies = [
            "AF_ATMPVC"
            "AF_ATMSVC"
            "AF_INET"
            "AF_INET6"
            "AF_IPX"
            "AF_NETLINK"
            "AF_PACKET"
            "AF_PPPOX"
            "AF_UNIX"
          ];
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          SecureBits = "no-setuid-fixup-locked noroot-locked";
          SystemCallFilter = "@system-service";
          SystemCallArchitectures = "native";

          # All pppd instances on a system must share a runtime
          # directory in order for PPP multilink to work correctly. So
          # we give all instances the same /run/pppd directory to store
          # things in.
          #
          # For the same reason, we can't set PrivateUsers=true, because
          # all instances need to run as the same user to access the
          # multilink database.
          RuntimeDirectory = "pppd";
          RuntimeDirectoryPreserve = true;
        };
      wantedBy = [ "multi-user.target" ];
    };

  systemd.timers."pppoe-restart" = {
    description = "restart pppoe daily";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:00:00";
      Unit = "pppoe-restart.service";
    };
  };

  systemd.services."pppoe-restart" = {
    description = "restart pppoe daily";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/systemctl try-restart pppd-ppp0.service";
    };
  };

  #systemd.services.nievpn.wantedBy = [ "multi-user.target" ];

  services.kaseinet = {
    enable = true;
    name = config.networking.hostName;
    v4addr = "10.10.0.6";
    v6addr = "fdcd:ad38:cdc5:3::6";
    ed25519PrivateKeyFile = "${config.sops.secrets.tinced25519.path}";
    extraConfig = ''
      ConnectTo = gz1
    '';
  };

  services.smartdns = {
    enable = true;
    settings = {
      bind = "[::]:53";
      bind-tcp = "[::]:53";
      cache-size = 262144; # 128MB
      cache-persist = false;
      #resolv-hostname = true;
      prefetch-domain = false;
      dualstack-ip-selection = false;
      log-console = true;
      log-size = "0";
      audit-enable = true;
      audit-console = true;
      audit-num = "0";
      conf-file = [
        "${pkgs.smartdns-china-list}/accelerated-domains.china.smartdns.conf"
        "${pkgs.smartdns-china-list}/apple.china.smartdns.conf"
        #"${pkgs.smartdns-china-list}/google.china.smartdns.conf"
        "${directdns}"
      ];
      server-tls = [
        #"2606:4700:4700::1111 -tls-host-verify cloudflare-dns.com"
        "1.1.1.1 -tls-host-verify cloudflare-dns.com -interface wgcf"
        "1.0.0.1 -tls-host-verify cloudflare-dns.com -interface wgcf"
        #"2400:3200::1 -tls-host-verify *.alidns.com -group china -exclude-default-group"
        #"223.5.5.5 -tls-host-verify *.alidns.com -group china -exclude-default-group"
        "1.12.12.12 -tls-host-verify 1.12.12.12 -group china -exclude-default-group -interface ${wanif} -subnet 120.235.1.1/16"
        "120.53.53.53 -tls-host-verify 120.53.53.53 -group china -exclude-default-group -interface ${wanif} -subnet 120.235.1.1/16"
      ];
      speed-check-mode = "none";
    };
  };

  services.resolved = {
    enable = false;
  };

  # https://github.com/NixOS/nixpkgs/pull/239028
  /*
    services.miniupnpd = {
    enable = false;
    natpmp = true;
    externalInterface = "${wanif}";
    internalIPs = [ "${lanif}" ];
    appendConfig = "";
    };
  */

  services.ddns = {
    enable = true;
    configFile = config.sops.secrets.ddns.path;
    environment = {
      "HTTP_PROXY" = "127.0.0.1:1080";
    };
  };

  services.ntpd-rs = {
    enable = true;
    metrics.enable = true;
    settings = {
      server = [
        { listen = "[::]:123"; }
      ];
    };
  };

  services.sing-box = {
    enable = true;
    settings = {
      log = {
        level = "info";
      };
      dns = {
        servers = [
          {
            tag = "cloudflare";
            address = "https://1.1.1.1/dns-query";
            strategy = "prefer_ipv6";
          }
          {
            tag = "local";
            address = "local";
            strategy = "prefer_ipv6";
          }
        ];
        rules = [{
          geosite = [ "cn" ];
          server = "local";
        }];
        final = "cloudflare";
      };
      inbounds = [
        {
          type = "mixed";
          tag = "inbound";
          listen = "::";
          listen_port = 1080;
          sniff = true;
          sniff_override_destination = true;
        }
        {
          type = "tun";
          tag = "tun-in";
          interface_name = "singbox";
          inet4_address = "172.19.0.1/30";
          inet6_address = "fdf0:dcba:9876::1/126";
          sniff = true;
          sniff_override_destination = true;
          auto_route = false;
          #auto_redirect = false;
        }
        {
          listen = "::";
          listen_port = 8688;
          tag = "ss-in";
          type = "shadowsocks";
          sniff = true;
          sniff_override_destination = true;
          method = "2022-blake3-aes-128-gcm";
          password = { _secret = "${config.sops.secrets.singboxpass.path}"; };
          multiplex = {
            enabled = true;
          };
        }
      ];
      outbounds = [
        {
          server = "2607:f130:0:179::2f6b:52ea";
          server_port = 443;
          tag = "tls-cone";
          type = "shadowtls";
          version = 3;
          password = { _secret = "${config.sops.secrets.singboxpass.path}"; };
          tls = {
            enabled = true;
            server_name = "kasei.im";
            utls = {
              enabled = true;
              fingerprint = "chrome";
            };
          };
        }
        {
          type = "shadowsocks";
          tag = "ss-cone";
          server = "2607:f130:0:179::2f6b:52ea";
          server_port = 9555;
          method = "2022-blake3-aes-128-gcm";
          password = { _secret = "${config.sops.secrets.singboxpass.path}"; };
          detour = "tls-cone";
          multiplex = {
            enabled = true;
            protocol = "h2mux";
          };
        }
        {
          type = "socks";
          tag = "r5c";
          server = "10.10.3.1";
          server_port = 1080;
          version = "5";
        }
        {
          type = "direct";
          tag = "wgcf";
          bind_interface = "wgcf";
        }
        {
          type = "direct";
          tag = "cmcc";
          bind_interface = "${wanif}";
        }
      ];
      route = {
        rules = [
          {
            geoip = [ "cn" ];
            outbound = "cmcc";
          }
          {
            domain_suffix = [
              # steam cdn
              "clngaa.com"
              "pphimalayanrt.com"
            ];
            outbound = "cmcc";
          }
          {
            geosite = [ "cn" ];
            outbound = "cmcc";
          }
          {
            domain_suffix = [
              "api.cloudflare.com" # ddns
              "openai.com"
              "hanime.tv"
            ];
            outbound = "tls-cone";
          }
        ];
        final = "wgcf";
      };
    };
  };

  services.chinaRoute = {
    fwmark = 200;
    enableV4 = true;
    enableV6 = true;
  };

  networking = {
    hostName = "n3160";
    useDHCP = false;
    firewall.enable = false;
    nat.enable = false;
    timeServers = [
      "ntp.aliyun.com"
      "ntp1.aliyun.com"
      "ntp2.aliyun.com"
      "ntp3.aliyun.com"
      "ntp4.aliyun.com"
      "ntp.tencent.com"
      "ntp1.tencent.com"
      "ntp2.tencent.com"
      "ntp3.tencent.com"
      "ntp4.tencent.com"
      "ntp5.tencent.com"
      "0.cn.pool.ntp.org"
      "1.cn.pool.ntp.org"
      "2.cn.pool.ntp.org"
      "3.cn.pool.ntp.org"
    ];
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
                66.103.210.62/32, # cone
                81.71.146.69/32, # gz2
                #37.27.0.0/16, # Hetzner, slow with warp
                #95.217.0.0/16,
                #163.172.0.0/16,
                #135.181.0.0/16,
                #51.158.0.0/15,
                #62.210.0.0/16,
              }
            }

            set kaseiserversv6 {
              type ipv6_addr
              flags constant, interval
              elements = {
                2607:f130:0:186::0/64, # cone
                2607:f130:0:17e::0/64, # cone
                2607:f130:0:179::0/64,
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

            set localnetv6 {
              type ipv6_addr
              flags constant, interval
              elements = {
                fc00::/7
              }
            }

            chain route-mark {
              ether saddr {2c:fd:a1:b1:e1:02, 
                2c:fd:a1:b1:e1:a1,
                9e:72:34:02:37:dd} mark set 200; # nas0
              ip daddr @localnet meta mark set 200
              ip daddr @kaseiserversv4 meta mark set 200
              ip6 daddr @localnetv6 meta mark set 200
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

            chain postrouting {
              type filter hook postrouting priority mangle + 10; policy accept;
              meta nfproto ipv4 counter accept
              meta nfproto ipv6 counter accept
            }
          '';
        };
        filter = {
          family = "inet";
          content = ''
            flowtable f {
              hook ingress priority filter;
              devices = { "${lanif}", "enp1s0" };
              counter
            }

            chain input {
              type filter hook input priority filter; policy accept;

              ct state established,related counter accept

              iifname { "${lanif}", "tinc.kaseinet", "lo" } counter accept

              meta l4proto {icmp, icmpv6, igmp} accept;

              tcp dport { 22, 655, 8688 } accept;
              udp dport { 22, 546, 655, 2480, 8688 } accept;

              iifname "${wanif}" drop
            }

            chain forward {
              type filter hook forward priority filter; policy accept;

              ct state established,related meta l4proto {tcp, udp} flow add @f counter;
              ct state established,related counter accept;

              tcp flags syn tcp option maxseg size set rt mtu;
              iifname "wgcf" tcp flags syn tcp option maxseg size set 1360;

              # 12526, qbitorrent
              meta l4proto {icmp, icmpv6, igmp} accept;
              tcp dport {22, 443, 12526 } accept;
              udp dport {22, 443, 12526 } accept;

              iifname { "${lanif}", "tinc.kaseinet" } counter accept;
              iifname "${wanif}" drop;
            }

            chain output {
              type filter hook output priority filter; policy accept;
              tcp flags syn tcp option maxseg size set rt mtu;
              iifname "wgcf" tcp flags syn tcp option maxseg size set 1360;
            }
          '';
        };
        nat = {
          family = "ip";
          content = ''
            # Setup NAT masquerading on the ${wanif} interface
            chain postrouting {
              type nat hook postrouting priority filter; policy accept;
              oifname {${wanif}, enp1s0, wgcf} masquerade
            }
          '';
        };
      };
    };

    useNetworkd = true;
    interfaces.enp1s0 = {
      useDHCP = false;
      #macAddress = "ec:6c:b5:2a:75:22"; # copy from cmcc router
      ipv4.addresses = [
        { address = "192.168.1.2"; prefixLength = 24; }
      ];
      ipv4.routes = [
        { address = "192.168.1.1"; prefixLength = 24; options = { Metric = "100"; }; }
      ];
    };

    vlans."cmccppp" = {
      id = 41;
      interface = "enp1s0";
    };
    vlans."cmcciptv" = {
      id = 48;
      interface = "enp1s0";
    };
    /*
      vlans."cmcctr069" = {
      id = 46;
      interface = "enp1s0";
      };
      vlans."cmccother" = {
      id = 50;
      interface = "enp1s0";
      };
    */

    interfaces."cmccppp" = {
      useDHCP = false;
    };
  };

  systemd.services.systemd-networkd.environment.SYSTEMD_LOG_LEVEL = "debug";
  systemd.network = {
    wait-online = {
      ignoredInterfaces = [ "cmccppp" "wgcf" "singbox" "ens1" "cmcciptv" "tinc.kaseinet" ];
    };
    networks = {
      "60-ppp0" = {
        matchConfig = {
          Name = "ppp0";
          Type = "ppp";
        };
        networkConfig = {
          DHCP = "ipv6";
          LLMNR = false;
          IPv6AcceptRA = true;
          IPv6ProxyNDP = false;
          KeepConfiguration = false;
          DHCPPrefixDelegation = false;
          DefaultRouteOnDevice = true;
        };
        dhcpV6Config = {
          UseAddress = "no";
          WithoutRA = "solicit";
          UseDNS = "no";
          UseNTP = "no";
          UseDelegatedPrefix = "yes";
          PrefixDelegationHint = "::/60";
        };
        dhcpPrefixDelegationConfig = {
          UplinkInterface = ":self";
          Announce = false;
        };
        routes = [
          {
            Gateway = "::";
            GatewayOnLink = true;
          }
        ];
        routingPolicyRules = [
          {
            Family = "both";
            FirewallMark = 200;
            Priority = 200;
            Table = 254; # main route table
          }
          {
            Family = "both";
            FirewallMark = 300;
            Priority = 300;
            Table = 300;
          }
        ];
      };
      "50-lan" = {
        matchConfig = {
          Name = "${lanif}";
        };
        address = [
          "10.10.2.1/24"
        ];
        routes = [
          { Destination = "10.10.2.0/24"; }
          { Destination = "fdcd:ad38:cdc5::/48"; }
        ];
        networkConfig = {
          DHCP = false;
          IPv6SendRA = true;
          IPv6ProxyNDP = false;
          DHCPPrefixDelegation = true;
          ConfigureWithoutCarrier = true;
          DHCPServer = true;
          # VLAN = [ "laniptv" ];
        };
        dhcpServerConfig = {
          PoolSize = 100;
          PoolOffset = 129;
          DNS = "_server_address";
          NTP = "_server_address";
          Timezone = "Asia/Shanghai";
          # https://www.iana.org/assignments/bootp-dhcp-parameters/bootp-dhcp-parameters.xhtml
          SendOption = "15:string:i.kasei.im";
        };
        dhcpServerStaticLeases = [
          { MACAddress = "4c:c6:4c:bd:41:bd"; Address = "10.10.2.10"; } # ax6000
          { MACAddress = "2c:fd:a1:b1:e1:02"; Address = "10.10.2.11"; } # nas0
          { MACAddress = "78:11:dc:b6:91:22"; Address = "10.10.2.176"; } # airpurifier
        ];
        ipv6SendRAConfig = {
          Managed = false;
          OtherInformation = true;
          EmitDNS = true;
          DNS = "_link_local";
          EmitDomains = true;
          Domains = config.networking.domain;
        };
        dhcpPrefixDelegationConfig = {
          UplinkInterface = "ppp0";
          Announce = true;
        };
        ipv6Prefixes = [
          {
            AddressAutoconfiguration = true;
            Prefix = "fdcd:ad38:cdc5:1::/64";
            Assign = true;
          }
        ];
      };
      "40-cmccppp" = {
        matchConfig = {
          Name = "cmccppp";
        };
        networkConfig = {
          DHCP = "no";
          LinkLocalAddressing = "no";
          KeepConfiguration = "static";
        };
      };

      "40-cmcciptv" = {
        matchConfig = {
          Name = "cmcciptv";
        };
        linkConfig = {
          #MACAddress = "ec:6c:b5:2a:75:22";
          MACAddress = "c4:74:1e:88:76:84"; # copy from zte
        };
        networkConfig = {
          DHCP = "ipv4";
          IPv6AcceptRA = false;
        };
        dhcpV4Config = {
          UseDNS = false;
          UseNTP = false;
          UseDomains = false;
          UseRoutes = true;
          RouteMetric = 2000;
          UseGateway = false;
        };
        routes = [
          {
            Destination = "183.235.16.92/32";
            Gateway = "_dhcp4";
          }
          {
            Destination = "239.0.0.0/8";
            Type = "multicast";
          }
        ];
      };
    };
  };

  networking.wireguard.interfaces."wgcf" = {
    ips = [
      "10.10.0.20/32"
      "fd80:13f7::10:10:0:20/128"
      "fdcd:ad38:cdc5:3:10:10:0:20/128"
    ];
    table = "300";
    fwMark = "0xc8"; # 200
    mtu = 1400;
    listenPort = 2480;
    privateKeyFile = "${config.sops.secrets.wireguard-key.path}";
    peers = [
      {
        publicKey = "1gxW3wgMyVpPHmOkIa7Ooj25nrUqfZCNKUzLWg8Diwg=";
        allowedIPs = [ "0.0.0.0/0" "::/0" ];
      }
    ];
  };
}



