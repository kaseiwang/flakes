{ config, pkgs, ... }:
with pkgs.lib;
let
  wanif = "ppp0";
  wanif-phy = "enp8s0";
  #lanif-phy = "enp7s0";
  lanif = "enp7s0";
in
{
  sops.secrets = {
    wgkey = {
      owner = "systemd-network";
    };
    ddns-token = { };
    singboxpass = { };
    ppp0-config = {
      path = "/etc/ppp/peers/ppp0";
      mode = "600";
    };
    ddns = { };
    wifipsk = { };
  };

  systemd.services."pppd-ppp0" =
    let
      name = "ppp0";
    in
    {
      before = [ "network.target" ];
      wants = [ "network.target" ];
      after = [
        "network-pre.target"
        "sops-nix.service"
      ];
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
      ];
      server-tls = [
        # bootstrap
        "223.5.5.5 -tls-host-verify *.alidns.com -group bootstrap-dns-cn -exclude-default-group -set-mark 200"
        "223.6.6.6 -tls-host-verify *.alidns.com -group bootstrap-dns-cn -exclude-default-group -set-mark 200"
        "1.1.1.1 -tls-host-verify cloudflare-dns.com -group bootstrap-dns-global -exclude-default-group -set-mark 300"
        "1.0.0.1 -tls-host-verify cloudflare-dns.com -group bootstrap-dns-global -exclude-default-group -set-mark 300"
        # oversea
        "one.one.one.one -set-mark 300"
        "dns.google -set-mark 300"
        # china
        "dot.pub -group china -exclude-default-group -set-mark 200"
        "dns.alidns.com -group china -exclude-default-group -set-mark 200"
      ];
      nameserver = [
        # dot bootstrap
        "/dot.pub/bootstrap-dns-cn"
        "/dns.alidns.com/bootstrap-dns-cn"
        "/one.one.one.one/bootstrap-dns-global"
        "/dns.google/bootstrap-dns-global"
        # extra china rules
        "/steamcontent.com/china"
      ];
      speed-check-mode = "none";
    };
  };

  services.resolved = {
    enable = false;
  };

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
            address = "tls://[2606:4700:4700::1111]";
            strategy = "prefer_ipv6";
            detour = "select";
          }
          {
            tag = "tencent";
            address = "tls://120.53.53.53";
            strategy = "prefer_ipv6";
            detour = "direct";
          }
        ];
        rules = [
          {
            rule_set = [
              "geosite-cn"
              "geoip-cn"
            ];
            server = "tencent";
            outbound = "direct";
          }
        ];
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
          type = "mixed";
          tag = "golocal";
          listen = "::";
          listen_port = 1070;
          sniff = false;
        }
        {
          listen = "::";
          listen_port = 8688;
          tag = "ss-in";
          type = "shadowsocks";
          sniff = true;
          sniff_override_destination = true;
          method = "2022-blake3-aes-128-gcm";
          password = {
            _secret = "${config.sops.secrets.singboxpass.path}";
          };
          multiplex = {
            enabled = true;
          };
        }
      ];
      outbounds = [
        {
          server = "2607:f130:0:179::2f6b:52ea";
          server_port = 443;
          tag = "tls-cone3";
          type = "shadowtls";
          version = 3;
          password = {
            _secret = "${config.sops.secrets.singboxpass.path}";
          };
          tls = {
            enabled = true;
            server_name = "kasei.im";
          };
        }
        {
          type = "shadowsocks";
          tag = "ss-cone3";
          server = "2607:f130:0:179::2f6b:52ea";
          server_port = 9555;
          method = "2022-blake3-aes-128-gcm";
          password = {
            _secret = "${config.sops.secrets.singboxpass.path}";
          };
          detour = "tls-cone3";
          multiplex = {
            enabled = true;
            protocol = "h2mux";
          };
        }
        {
          server = "74.48.96.113";
          server_port = 443;
          tag = "tls-cone2";
          type = "shadowtls";
          version = 3;
          password = {
            _secret = "${config.sops.secrets.singboxpass.path}";
          };
          tls = {
            enabled = true;
            server_name = "kasei.im";
          };
        }
        {
          type = "shadowsocks";
          tag = "ss-cone2";
          server = "74.48.96.113";
          server_port = 9555;
          method = "2022-blake3-aes-128-gcm";
          password = {
            _secret = "${config.sops.secrets.singboxpass.path}";
          };
          detour = "tls-cone2";
          multiplex = {
            enabled = true;
            protocol = "h2mux";
          };
        }
        {
          type = "selector";
          tag = "select";
          outbounds = [
            "ss-cone3"
            "ss-cone2"
          ];
        }
        {
          type = "direct";
          tag = "direct";
          routing_mark = 200;
        }
      ];
      route = {
        default_mark = 200;
        rules = [
          {
            inbound = "golocal";
            outbound = "direct";
          }
          {
            ip_is_private = true;
            outbound = "direct";
          }
          {
            rule_set = "geoip-cn";
            outbound = "direct";
          }
          {
            rule_set = "geosite-cn";
            outbound = "direct";
          }
          {
            domain = [
              "bt.kasei.im"
              "yarr.kasei.im"
              "chat.kasei.im"
              "grafana.kasei.im"
              "nextcloud.kasei.im"
            ];
            domain_suffix = [
              # steam cdn
              "clngaa.com"
              "steamcontent.com"
              "pphimalayanrt.com"
            ];
            outbound = "direct";
          }
        ];
        rule_set = [
          {
            tag = "geoip-cn";
            type = "local";
            format = "binary";
            path = "${pkgs.sing-geoip}/share/sing-box/rule-set/geoip-cn.srs";
          }
          {
            tag = "geosite-cn";
            type = "local";
            format = "binary";
            path = "${pkgs.sing-geosite}/share/sing-box/rule-set/geosite-cn.srs";
          }
        ];
        final = "select";
      };
    };
  };

  services.chinaRoute = {
    fwmark = 200;
    enableV4 = true;
    enableV6 = true;
  };

  networking = {
    hostName = "nas0";
    hostId = pkgs.lib.concatStringsSep "" (
      pkgs.lib.take 8 (
        pkgs.lib.stringToCharacters (builtins.hashString "sha256" config.networking.hostName)
      )
    );

    useDHCP = false;
    useNetworkd = true;
    firewall.enable = false;
    nat.enable = false;

    #wireless = {
    #  enable = true;
    #  secretsFile = "${config.sops.secrets.wireless.path}";
    #  networks = {
    #    kaseinet.pskRaw = "ext:psk_kaseinet";
    #  };
    #};

    nftables = {
      enable = true;
      flattenRulesetFile = true;
      preCheckRuleset = ''
        sed 's/.*devices.*/devices = { lo }/g' -i ruleset.conf
        sed 's/skuid ${config.services.qbittorrent.user}/skuid nobody/g' -i ruleset.conf
      '';
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
              ip daddr @localnet meta mark set 200
              ip daddr @kaseiserversv4 meta mark set 200
              ip dscp lephb meta mark set 200
              ip6 daddr @localnetv6 meta mark set 200
              ip6 dscp lephb meta mark set 200

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
              devices = { "${lanif}", "${wanif-phy}" };
              counter
            }

            chain input {
              type filter hook input priority filter; policy accept;

              ct state established,related counter accept

              iifname { "${lanif}", "tinc.kaseinet", "lo" } counter accept

              meta l4proto {icmp, icmpv6, igmp} accept;

              # dhcpv6
              iifname ${wanif} udp dport 546 accept;

              # 22, ssh
              # 2480, wireguard
              # 8688, proxy
              # 6771, 12526, 57299, bittorrent
              tcp dport { 22, 8688, 6771, 12526, 57299 } accept;
              udp dport { 22, 2480, 8688, 6771, 12526, 57299 } accept;

              iifname "${wanif}" drop
            }

            chain forward {
              type filter hook forward priority filter; policy accept;

              ct state established,related meta l4proto {tcp, udp} flow add @f counter;
              ct state established,related counter accept;

              tcp flags syn tcp option maxseg size set rt mtu;
              iifname "wg0" tcp flags syn tcp option maxseg size set 1360;

              # 12526, qbitorrent
              meta l4proto {icmp, icmpv6, igmp} accept;
              tcp dport {22, 443 } accept;
              udp dport {22, 443 } accept;

              iifname { "${lanif}", "tinc.kaseinet" } counter accept;
              iifname "${wanif}" drop;
            }

            chain output {
              type filter hook output priority filter; policy accept;
              tcp flags syn tcp option maxseg size set rt mtu;
              iifname "wg0" tcp flags syn tcp option maxseg size set 1360;
            }
          '';
        };
        nat = {
          family = "ip";
          content = ''
            # Setup NAT masquerading on the ${wanif} interface
            chain postrouting {
              type nat hook postrouting priority filter; policy accept;
              oifname {${wanif}, ${wanif-phy} } masquerade
              oifname wg0 ip saddr 10.70.0.0/16 masquerade
            }
          '';
        };
        qos = {
          family = "inet";
          content = ''
            chain output {
              type filter hook output priority filter; policy accept;
              skuid ${config.services.qbittorrent.user} ip dscp set lephb counter
              skuid ${config.services.qbittorrent.user} ip6 dscp set lephb counter
            }
          '';
        };
      };
    };

    interfaces.enp6s0 = {
      useDHCP = true;
    };

    interfaces."${wanif-phy}" = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "192.168.1.2";
          prefixLength = 24;
        }
      ];
      ipv4.routes = [
        {
          address = "192.168.1.1";
          prefixLength = 24;
          options = {
            Metric = "100";
          };
        }
      ];
    };

    interfaces."cuccppp" = {
      useDHCP = false;
    };

    vlans."cuccppp" = {
      id = 3961;
      interface = "${wanif-phy}";
    };

  };

  systemd.services.systemd-networkd.environment.SYSTEMD_LOG_LEVEL = "debug";
  systemd.network = {
    wait-online = {
      ignoredInterfaces = [
        "cuccppp"
        "wg0"
        "enp6s0"
        "enp7s0"
      ];
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
          RouteTable = 300;
        };
        wireguardPeers = [
          {
            PublicKey = "c1OdyFkvCBz7DvuCNCIxUQH4kLxGocOOILodtSnmwRk=";
            Endpoint = "[2607:f130:0:179::2f6b:52ea]:2480";
            PersistentKeepalive = 60;
            AllowedIPs = [
              "0.0.0.0/0"
              "::/0"
              "10.10.0.21/32"
              "fdcd:ad38:cdc5:3:10:10:0:21/128"
            ];
          }
        ];
      };
    };
    networks = {
      "40-cuccppp" = {
        matchConfig = {
          Name = "cuccppp";
        };
        networkConfig = {
          DHCP = "no";
          LinkLocalAddressing = "no";
        };
      };
      "50-${wanif}" = {
        matchConfig = {
          Name = "${wanif}";
          Type = "ppp";
        };
        networkConfig = {
          DHCP = "ipv6";
          LLMNR = false;
          IPv6AcceptRA = true;
          IPv6ProxyNDP = false;
          KeepConfiguration = "static";
          DHCPPrefixDelegation = false;
          DefaultRouteOnDevice = true;
        };
        dhcpV6Config = {
          UseAddress = "yes";
          WithoutRA = "solicit";
          UseDNS = "no";
          UseNTP = "no";
          UseDelegatedPrefix = "yes";
          PrefixDelegationHint = "::/60";
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
      "70-lan" = {
        matchConfig = {
          Name = "${lanif}";
        };
        address = [
          "10.10.2.1/24"
          "fdcd:ad38:cdc5:1::2"
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
          # https://www.iana.org/assignments/bootp-dhcp-parameters/bootp-dhcp-parameters.xhtml
          SendOption = "15:string:i.kasei.im";
        };
        dhcpServerStaticLeases = [
          {
            MACAddress = "4c:c6:4c:bd:41:bd";
            Address = "10.10.2.10";
          } # ax6000
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
          UplinkInterface = "${wanif}";
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
      "75-wg0" = {
        matchConfig = {
          Name = "wg0";
        };
        address = [
          "10.10.0.20/32"
          "fdcd:ad38:cdc5:3:10:10:0:20/128"
        ];
        routes = [
          { Destination = "10.10.0.21/32"; }
          { Destination = "fdcd:ad38:cdc5:3:10:10:0:21/128"; }
        ];
        networkConfig = {
          DHCP = false;
        };
      };
    };
  };
}
