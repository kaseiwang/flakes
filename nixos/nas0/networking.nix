{ config, pkgs, ... }:
with pkgs.lib;
let
  wanif = "ppp0";
  wanif-phy = "enp8s0";
  lanif = "enp7s0";
  lan2if = "enp6s0";
  localRouteMark = 200;
  overlayRouteMark = 300;
  overlayRouteTable = 300;
  overPort = 2481;
  overNetdevFiles = [
    "20-over-bridge.netdev"
    "20-over-vlan.netdev"
  ];
  overBridgePort = {
    linkConfig = {
      RequiredForOnline = false;
      MTUBytes = 1380;
    };
    networkConfig = {
      Bridge = "brover10";
      ConfigureWithoutCarrier = true;
      IPv4Forwarding = false;
      IPv6Forwarding = false;
    };
  };
  # Persistent guards are outside nftables.tables so stopping the main firewall
  # cannot delete them. Both loaders replace them in a single nft transaction.
  overHostFirewall = ''
    destroy table bridge kaseinetover_bridge_guard
    table bridge kaseinetover_bridge_guard {
      chain input {
        type filter hook input priority -10; policy accept;
        iifname { "vlanover10", "over10" } drop
      }
      chain output {
        type filter hook output priority -10; policy accept;
        oifname { "vlanover10", "over10" } drop
      }
      chain forward {
        type filter hook forward priority -10; policy accept;
        iifname "vlanover10" oifname "over10" ether type { ip, arp } accept
        iifname "over10" oifname "vlanover10" ether type { ip, arp } accept
        iifname { "vlanover10", "over10" } drop
        oifname { "vlanover10", "over10" } drop
      }
    }
    destroy table inet kaseinetover_host_guard
    table inet kaseinetover_host_guard {
      chain input {
        type filter hook input priority -10; policy accept;
        iifname { "brover10", "vlanover10", "over10", "wgover" } drop
      }
      chain output {
        type filter hook output priority -10; policy accept;
        oifname { "brover10", "vlanover10", "over10", "wgover" } drop
      }
      # Block unenslaved ports during link setup and WG returned by nspawn.
      # br_netfilter presents enslaved ports as brover10 here; bridge hooks
      # handle that path so legitimate VLAN <-> veth forwarding still works.
      chain forward {
        type filter hook forward priority -10; policy accept;
        iifname { "vlanover10", "over10", "wgover" } drop
        oifname { "vlanover10", "over10", "wgover" } drop
      }
    }
  '';
in
{
  sops.secrets = {
    wgover-key.restartUnits = [ "container@kaseinetover.service" ];
    kaseinetover-domains.restartUnits = [ "container@kaseinetover.service" ];
    wgkey = {
      owner = "systemd-network";
    };
    ddns-token = { };
    singboxpass = { };
    ppp0-secrtes = {
      path = "/etc/ppp/options";
      mode = "400";
    };
    ddns = { };
    wifipsk = { };
  };

  # nspawn owns the namespace, WG transfer and the dedicated Wi-Fi veth pair.
  containers.kaseinetover = {
    autoStart = true;
    privateNetwork = true;
    # Let the container's time.timeZone own /etc/localtime, not nspawn's host copy.
    extraFlags = [ "--timezone=off" ];
    interfaces = [ "wgover" ];
    # Both ends are named over10, in different namespaces. networkd attaches
    # the host end to brover10; all IP configuration lives in the container.
    extraVeths.over10 = { };
    # Use the outer host config's secret path on both sides of the mount.
    # /run/keys is overmounted by the container's boot process.
    bindMounts = {
      "${config.sops.secrets.wgover-key.path}" = {
        hostPath = config.sops.secrets.wgover-key.path;
      };
      "${config.sops.secrets.kaseinetover-domains.path}" = {
        hostPath = config.sops.secrets.kaseinetover-domains.path;
      };
    };
    config = { lib, ... }: {
      imports = [ ./kaseinetover-proxy.nix ];
      services.kaseinetover-proxy.domainSuffixesFile = config.sops.secrets.kaseinetover-domains.path;
      system.stateVersion = "26.11";
      time.timeZone = "America/Los_Angeles";
      networking = {
        useNetworkd = true;
        useHostResolvConf = false;
        enableIPv6 = false;
        firewall.enable = false;
        wireguard = {
          interfaces = {
            wgover = {
              privateKeyFile = config.sops.secrets.wgover-key.path;
              listenPort = overPort;
              fwMark = "200";
              mtu = 1380;
              ips = [ "10.203.0.1/30" ];
              allowedIPsAsRoutes = false;
              peers = [
                {
                  publicKey = "k4QhCtsNJYywFsIU7Uk/ci8hdFxDQgZKlMX13anrL0I=";
                  allowedIPs = [ "0.0.0.0/0" ];
                  endpoint = "[2607:f130:0:179::2f6b:52ea]:${toString overPort}";
                  persistentKeepalive = 25;
                }
                {
                  # devbox initiates the connection to cmcc.i.kasei.im:2481.
                  publicKey = "H05j10qr+RXFULmdU/yqZIAtHutMMrN7Et4x+P7bBmo=";
                  allowedIPs = [ "10.203.1.2/32" ];
                }
              ];
            };
          };
        };
      };
      # The tunnel endpoint is numeric; no DNS lookup is needed here.
      services.resolved.enable = false;
      system.nssDatabases.hosts = lib.mkForce [ "files" ];
      boot.kernel.sysctl = {
        "net.ipv4.ip_forward" = 1;
        "net.ipv4.conf.all.rp_filter" = 0;
        "net.ipv4.conf.default.rp_filter" = 0;
        "net.ipv4.conf.all.send_redirects" = 0;
        "net.ipv4.conf.default.send_redirects" = 0;
        "net.ipv4.conf.all.accept_redirects" = 0;
        "net.ipv4.conf.default.accept_redirects" = 0;
      };
      systemd.network = {
        # Startup/endpoint resolution must not wait for VPN connectivity.
        wait-online.enable = false;
        config.networkConfig.IPv4Forwarding = true;
        networks = {
          "10-lo" = {
            matchConfig.Name = "lo";
            routes = [
              {
                Destination = "0.0.0.0/0";
                Type = "blackhole";
                Metric = 32760;
              }
            ];
          };
          "40-wgover" = {
            linkConfig.RequiredForOnline = false;
            networkConfig = {
              LinkLocalAddressing = "no";
            };
            routes = [
              {
                Destination = "10.203.1.2/32";
                PreferredSource = "10.203.0.1";
              }
              {
                Destination = "0.0.0.0/0";
                Metric = 10;
              }
            ];
          };
          "40-over10" = {
            matchConfig.Name = "over10";
            address = [ "10.10.10.1/24" ];
            linkConfig.MTUBytes = 1380;
            networkConfig = {
              DHCPServer = true;
              LinkLocalAddressing = "no";
              ConfigureWithoutCarrier = true;
            };
            dhcpServerConfig = {
              PoolOffset = 100;
              PoolSize = 100;
              DefaultLeaseTimeSec = "12h";
              DNS = [
                "10.10.10.1"
              ];
              EmitNTP = false;
              Timezone = "America/Los_Angeles";
              SendOption = "26:uint16:1380";
            };
          };
        };
      };
      # Load MSS clamping before configuring the container's network.
      systemd.services.systemd-networkd = {
        requires = [ "nftables.service" ];
        after = [ "nftables.service" ];
      };
    };
  };

  # The host's script backend is provided by NixOS. Unlike host networkd netdevs,
  # it does not recreate a same-named WG while the real device is in the container.
  networking.wireguard = {
    useNetworkd = false;
    interfaces = {
      wgover = {
        privateKeyFile = config.sops.secrets.wgover-key.path;
        mtu = 1380;
        fwMark = "200";
        allowedIPsAsRoutes = false;
      };
    };
  };
  systemd.services = {
    kaseinetover-host-guard = {
      description = "Isolate the kaseinetover bridge and host WireGuard interface";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.nftables}/bin/nft -f ${pkgs.writeText "kaseinetover-host-guard.nft" overHostFirewall}";
        # No ExecStop: interfaces may survive networkd/container shutdown.
      };
    };
    systemd-networkd = {
      # systemd 262 can create these new netdevs on reload. Move only these two
      # files out of NixOS's default restart triggers; keep the existing host
      # netdev/link/global-config restart policy and wait-online unit unchanged.
      restartTriggers = mkForce (
        map (name: config.environment.etc."systemd/network/${name}".source) (
          filter (name: !hasSuffix ".network" name && !elem name overNetdevFiles) (
            attrNames config.systemd.network.units
          )
        )
        ++ [ config.environment.etc."systemd/networkd.conf".source ]
      );
      reloadTriggers = map (
        name: config.environment.etc."systemd/network/${name}".source
      ) overNetdevFiles;
    };
    kaseinetover-links = {
      description = "Enable the isolated kaseinetover bridge and VLAN";
      partOf = [ "container@kaseinetover.service" ];
      requires = [
        "kaseinetover-host-guard.service"
        "sys-subsystem-net-devices-brover10.device"
        "sys-subsystem-net-devices-vlanover10.device"
      ];
      after = [
        "kaseinetover-host-guard.service"
        "sys-subsystem-net-devices-brover10.device"
        "sys-subsystem-net-devices-vlanover10.device"
      ];
      # Bound waiting for missing devices without involving network.target or
      # the host's networkd/wait-online. Only the container depends on this job.
      unitConfig.JobTimeoutSec = "45s";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "15s";
        TimeoutStopSec = "15s";
        ExecStart = [
          "${pkgs.iproute2}/bin/ip link set dev brover10 up"
          "${pkgs.iproute2}/bin/ip link set dev vlanover10 up"
        ];
        # Also run after a partially failed start. Never touch the parent NIC.
        ExecStopPost = [
          "-${pkgs.iproute2}/bin/ip link set dev vlanover10 down"
          "-${pkgs.iproute2}/bin/ip link set dev brover10 down"
        ];
      };
    };
    "wireguard-wgover" = {
      partOf = [ "container@kaseinetover.service" ];
      # The native WG module orders this before network.target by default.
      # A container-only tunnel must not delay the host's network startup.
      before = mkForce [ ];
      requires = [
        "kaseinetover-host-guard.service"
      ]
      ++ optional config.sops.useSystemdActivation "sops-install-secrets.service";
      after = [
        "kaseinetover-host-guard.service"
        "sops-install-secrets.service"
      ];
    };
    "container@kaseinetover" = {
      requires = [
        "wireguard-wgover.service"
        "kaseinetover-links.service"
        "kaseinetover-host-guard.service"
      ];
      after = [
        "wireguard-wgover.service"
        "kaseinetover-links.service"
        "kaseinetover-host-guard.service"
      ];
    };
  };
  services = {
    pppd = {
      enable = true;
      peers = {
        ppp0 = {
          config = ''
            updetach
            plugin pppoe.so cuccppp
            debug

            noauth
            defaultroute
            maxfail "5"

            lcp-echo-interval "3"
            lcp-echo-failure "20"

            mru 1492
            mtu 1492
          '';
        };
      };
    };

    smartdns = {
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
          "${pkgs.smartdns-china-list}/google.china.smartdns.conf"
        ];
        server-tls = [
          # bootstrap
          "223.5.5.5 -tls-host-verify *.alidns.com -group bootstrap-dns-cn -exclude-default-group -set-mark ${toString localRouteMark}"
          "223.6.6.6 -tls-host-verify *.alidns.com -group bootstrap-dns-cn -exclude-default-group -set-mark ${toString localRouteMark}"
          "1.1.1.1 -tls-host-verify cloudflare-dns.com -group bootstrap-dns-global -exclude-default-group -set-mark ${toString overlayRouteMark}"
          "1.0.0.1 -tls-host-verify cloudflare-dns.com -group bootstrap-dns-global -exclude-default-group -set-mark ${toString overlayRouteMark}"
          # oversea
          "one.one.one.one -set-mark ${toString overlayRouteMark}"
          "dns.google -set-mark ${toString overlayRouteMark}"
          # china
          "dot.pub -group china -exclude-default-group -set-mark ${toString localRouteMark}"
          "dns.alidns.com -group china -exclude-default-group -set-mark ${toString localRouteMark}"
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
        address = [
          "/cmcc.i.kasei.im/10.10.2.1,fdcd:ad38:cdc5:1::2"
        ];
        speed-check-mode = "none";
      };
    };

    resolved.enable = false;

    ddns = {
      enable = true;
      configFile = config.sops.secrets.ddns.path;
      environment = {
        "HTTP_PROXY" = "127.0.0.1:1080";
      };
    };

    ntpd-rs = {
      enable = true;
      metrics.enable = true;
      settings = {
        server = [
          { listen = "[::]:123"; }
        ];
      };
    };

    singbox-client = {
      enable = true;
      sercretPath = config.sops.secrets.singboxpass.path;
    };

    chinaRoute = {
      fwmark = localRouteMark;
      enableV4 = true;
      enableV6 = true;
    };
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
      flushRuleset = false;
      # Also restore the guards atomically if an old generation's deletions file
      # contains `flush ruleset`. Raw ruleset tables are not deleted on stop.
      ruleset = overHostFirewall;
      # china-route also uses a raw ruleset; retain its replace-on-reload/stop
      # behavior while leaving only the isolation guards persistent.
      extraDeletions = "destroy table inet china-route";
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
                163.47.135.141/32, # cone
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
              ip daddr @localnet meta mark set ${toString localRouteMark}
              ip daddr @kaseiserversv4 meta mark set ${toString localRouteMark}
              ip6 daddr @localnetv6 meta mark set ${toString localRouteMark}

              meta mark 0 ether saddr { 84:9e:56:79:14:c3, 70:a8:d3:57:5d:3c } meta mark set ${toString overlayRouteMark}
              # meta mark 0 meta mark set ${toString overlayRouteMark}
              meta mark ${toString localRouteMark} counter
              meta mark ${toString overlayRouteMark} counter
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
              devices = { "${lanif}", "${lan2if}", "${wanif-phy}" };
              counter
            }

            chain input {
              type filter hook input priority filter; policy accept;

              ct state established,related counter accept

              iifname { "${lanif}", "${lan2if}", "tinc.kaseinet", "lo" } counter accept

              meta l4proto {icmp, icmpv6, igmp} accept;

              # dhcpv6
              iifname ${wanif} udp dport 546 accept;

              # 22, ssh
              # 443/udp, HTTP/3 (QUIC)
              # 2480/2481, WireGuard underlay
              # 8688, proxy
              # 6771, 12526, 57299, bittorrent
              tcp dport { 22, 8688, 6771, 12526, 57299 } accept;
              udp dport { 22, 443, 2480, ${toString overPort}, 8688, 6771, 12526, 57299 } accept;

              iifname "${wanif}" drop
            }

            chain forward {
              type filter hook forward priority filter; policy accept;

              tcp flags syn tcp option maxseg size set rt mtu;

              ct state established,related meta l4proto {tcp, udp} flow add @f counter;
              ct state established,related counter accept;

              # 12526, qbitorrent
              meta l4proto {icmp, icmpv6, igmp} accept;
              tcp dport {22, 443 } accept;
              udp dport {22, 443 } accept;

              iifname { "${lanif}", "${lan2if}" , "tinc.kaseinet" } counter accept;
              iifname "${wanif}" drop;
            }

            chain output {
              type filter hook output priority filter; policy accept;
              tcp flags syn tcp option maxseg size set rt mtu;
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
              skuid ${config.services.qbittorrent.user} meta mark ${toString localRouteMark} counter
            }
          '';
        };
      };
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
        "${lanif}"
        "${lan2if}"
      ];
    };
    netdevs = {
      "20-over-vlan" = {
        netdevConfig = {
          Name = "vlanover10";
          Kind = "vlan";
          MTUBytes = 1380;
        };
        vlanConfig.Id = 10;
      };
      "20-over-bridge" = {
        netdevConfig = {
          Name = "brover10";
          Kind = "bridge";
          MTUBytes = 1380;
        };
        bridgeConfig = {
          STP = false;
          MulticastSnooping = false;
        };
      };
      "20-wg0" = {
        netdevConfig = {
          Name = "wg0";
          Kind = "wireguard";
          MTUBytes = 1408; # round down to 16bytes
        };
        wireguardConfig = {
          ListenPort = 2480;
          FirewallMark = localRouteMark; # go underlay
          PrivateKeyFile = "${config.sops.secrets.wgkey.path}";
          RouteTable = overlayRouteTable;
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
      "10-kaseinetover-unmanaged" = {
        matchConfig.Name = "wgover";
        linkConfig.Unmanaged = true;
      };
      # Dedicated L2 segment: neither the bridge nor either port gets an IP.
      "30-over-bridge" = {
        matchConfig.Name = "brover10";
        linkConfig = {
          RequiredForOnline = false;
          ActivationPolicy = "manual";
        };
        networkConfig = {
          LinkLocalAddressing = "no";
          ConfigureWithoutCarrier = true;
          IPv4Forwarding = false;
          IPv6Forwarding = false;
        };
      };
      # VLAN ingress stays DOWN until the guard-gated service enables it.
      "30-over-vlan" = recursiveUpdate overBridgePort {
        matchConfig.Name = "vlanover10";
        linkConfig.ActivationPolicy = "manual";
      };
      # nspawn creates this veth only after the same guard has succeeded.
      "30-over-ports" = overBridgePort // {
        matchConfig.Name = "over10";
      };
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
            FirewallMark = localRouteMark;
            Priority = 200;
            Table = 254; # main route table
          }
          {
            Family = "both";
            FirewallMark = overlayRouteMark;
            Priority = 300;
            Table = overlayRouteTable;
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
          { Destination = "fdcd:ad38:cdc5:1::/64"; }
        ];
        networkConfig = {
          DHCP = false;
          IPv6SendRA = true;
          IPv6ProxyNDP = false;
          DHCPPrefixDelegation = true;
          ConfigureWithoutCarrier = true;
          DHCPServer = true;
        };
        dhcpServerConfig = {
          PoolSize = 100;
          PoolOffset = 129;
          DNS = "_server_address";
          NTP = "_server_address";
          EmitDomain = true;
          Domain = config.networking.domain;
        };
        dhcpServerStaticLeases = [
          {
            MACAddress = "4c:c6:4c:bd:41:bd";
            Address = "10.10.2.10";
          } # ax6000
        ];
        ipv6SendRAConfig = {
          Managed = false;
          OtherInformation = false;
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
        ipv6RoutePrefixes = [
          {
            Route = "fdcd:ad38:cdc5:5::/64";
            Preference = "high";
          }
        ];
      };
      "71-lan2" = {
        matchConfig = {
          Name = "${lan2if}";
        };
        address = [
          "10.10.5.1/24"
          "fdcd:ad38:cdc5:5::1"
        ];
        routes = [
          { Destination = "10.10.5.0/24"; }
          { Destination = "fdcd:ad38:cdc5:5::/64"; }
        ];
        networkConfig = {
          VLAN = [ "vlanover10" ];
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
          # RFC 3442 classless static routes:
          #   0.0.0.0/0  via 10.10.5.1
          #   10.10.2.0/24 via 10.10.5.1
          # Keep the default route here because clients ignore the Router
          # option when a classless static route option is present.
          SendOption = "121:string:\\x00\\x0a\\x0a\\x05\\x01\\x18\\x0a\\x0a\\x02\\x0a\\x0a\\x05\\x01";
          EmitDomain = true;
          Domain = config.networking.domain;
        };
        dhcpServerStaticLeases = [
          {
            MACAddress = "4c:c6:4c:bd:41:bd";
            Address = "10.10.5.10";
          } # ax6000
          {
            MACAddress = "cc:b5:d1:31:5b:8a";
            Address = "10.10.5.164";
          } # qingping air monitor lite
          {
            MACAddress = "d4:43:8a:70:55:04";
            Address = "10.10.5.189";
          } # xiaomi heater ma3
        ];
        ipv6SendRAConfig = {
          Managed = false;
          OtherInformation = false;
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
            Prefix = "fdcd:ad38:cdc5:5::/64";
            Assign = true;
          }
        ];
        ipv6RoutePrefixes = [
          {
            Route = "fdcd:ad38:cdc5:1::/64";
            Preference = "high";
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
