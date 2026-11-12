{ config, pkgs, ... }:
let
  wanif = "ens3";
  overPort = 2481;
  verizonPeer = "jOe62jDrCrtnliHT9foTN930/19Rtlc7UMNdcCE51ho=";
  overFirewall = ''
    table inet over_filter {
      chain input {
        type filter hook input priority filter; policy drop;
        iifname "lo" accept
      }
      chain forward {
        type filter hook forward priority filter; policy drop;
        ct state invalid drop
        iifname "wgover" oifname "wgverizon" ip saddr 10.10.10.0/24 accept
        iifname "wgverizon" oifname "wgover" ip daddr 10.10.10.0/24 ct state established,related accept
      }
      chain mss {
        type filter hook forward priority mangle; policy accept;
        meta nfproto ipv4 tcp flags & (syn | rst) == syn tcp option maxseg size > 1340 tcp option maxseg size set 1340
      }
    }
    table ip over_nat {
      chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        oifname "wgverizon" ip saddr 10.10.10.0/24 snat to 10.7.0.2
      }
    }
  '';
  overHostFirewall = pkgs.writeText "kaseinetover-host-guard.nft" ''
    destroy table inet kaseinetover_host_guard
    table inet kaseinetover_host_guard {
      chain input {
        type filter hook input priority -10; policy accept;
        iifname { "wgover", "wgverizon" } drop
      }
      chain output {
        type filter hook output priority -10; policy accept;
        oifname { "wgover", "wgverizon" } drop
      }
      chain forward {
        type filter hook forward priority -10; policy accept;
        iifname { "wgover", "wgverizon" } drop
        oifname { "wgover", "wgverizon" } drop
      }
    }
  '';
  warpPort = 52408;
  warpBpf = pkgs.callPackage ../../pkgs/wgcf_bpf {
    clientId = "0xd3, 0xe3, 0x35";
    localPort = warpPort;
  };
in
with pkgs.lib;
{
  sops.secrets = {
    wgover-key.restartUnits = [ "container@kaseinetover.service" ];
    wgcf-key = {
      owner = "systemd-network";
    };
    wgverizon-key = {
      restartUnits = [ "container@kaseinetover.service" ];
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
        overPort
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

  # nspawn owns namespace creation and interface transfer. No management veth.
  containers.kaseinetover = {
    autoStart = true;
    privateNetwork = true;
    # Let the container's time.timeZone own /etc/localtime, not nspawn's host copy.
    extraFlags = [ "--timezone=off" ];
    interfaces = [
      "wgover"
      "wgverizon"
    ];
    # Use the outer host config's secret paths on both sides of each mount.
    # /run/keys is overmounted by the container's boot process.
    bindMounts = {
      "${config.sops.secrets.wgover-key.path}" = {
        hostPath = config.sops.secrets.wgover-key.path;
      };
      "${config.sops.secrets.wgverizon-key.path}" = {
        hostPath = config.sops.secrets.wgverizon-key.path;
      };
      # Mount the directory, not the socket inode: resolver restarts replace sockets.
      "/run/systemd/resolve" = {
        hostPath = "/run/systemd/resolve";
      };
    };
    config = { lib, ... }: {
      system.stateVersion = "26.11";
      time.timeZone = "America/Los_Angeles";
      networking = {
        useNetworkd = true;
        useHostResolvConf = false;
        enableIPv6 = false;
        firewall.enable = false;
        nftables = {
          enable = true;
          ruleset = overFirewall;
        };
        wireguard = {
          interfaces = {
            wgover = {
              privateKeyFile = config.sops.secrets.wgover-key.path;
              listenPort = overPort;
              fwMark = "200";
              mtu = 1380;
              ips = [ "10.203.0.2/30" ];
              allowedIPsAsRoutes = false;
              peers = [
                {
                  publicKey = "zBK0adI3l1SpGo/hP8+7esMbxJ8UhgXeP1sQnuDj4mc=";
                  allowedIPs = [
                    "10.10.10.0/24"
                    "10.203.0.1/32"
                  ];
                }
              ];
            };
            wgverizon = {
              privateKeyFile = config.sops.secrets.wgverizon-key.path;
              fwMark = "200";
              mtu = 1380;
              ips = [ "10.7.0.2/32" ];
              allowedIPsAsRoutes = false;
              peers = [
                {
                  publicKey = verizonPeer;
                  endpoint = "i.i1j.net:33329";
                  allowedIPs = [ "0.0.0.0/0" ];
                  persistentKeepalive = 25;
                }
              ];
            };
          };
        };
      };
      # Endpoint DNS goes through the host resolver Unix socket, not the VPN.
      services.resolved.enable = false;
      system.nssDatabases.hosts = lib.mkForce [
        "files"
        "resolve"
      ];
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
                Destination = "10.10.10.0/24";
                Metric = 10;
              }
            ];
          };
          "40-wgverizon" = {
            linkConfig.RequiredForOnline = false;
            networkConfig = {
              LinkLocalAddressing = "no";
            };
            routes = [
              {
                Destination = "0.0.0.0/0";
                Metric = 10;
              }
            ];
          };
        };
      };
      # Resolve via host NSS first, then change only this peer's endpoint. A DNS
      # failure exits before the netlink update, preserving the working endpoint.
      # Do not touch the .netdev: networkd reload would replace the entire peer.
      systemd.services.wireguard-endpoint-refresh-wgverizon = {
        description = "Refresh wgverizon endpoint through the host resolver";
        requires = [ "systemd-networkd.service" ];
        after = [ "systemd-networkd.service" ];
        environment.WG_ENDPOINT_RESOLUTION_RETRIES = "0";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.wireguard-tools}/bin/wg set wgverizon peer ${verizonPeer} endpoint i.i1j.net:33329";
          TimeoutStartSec = "30s";
        };
      };
      systemd.timers.wireguard-endpoint-refresh-wgverizon = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "1min";
          OnUnitActiveSec = "1min";
          AccuracySec = "1s";
        };
      };
      # Fail closed if the firewall cannot load, including initial container boot.
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
      wgverizon = {
        privateKeyFile = config.sops.secrets.wgverizon-key.path;
        mtu = 1380;
        fwMark = "200";
        allowedIPsAsRoutes = false;
      };
    };
  };
  systemd.services = {
    "wireguard-wgover" = {
      partOf = [ "container@kaseinetover.service" ];
      requires = [
        "kaseinetover-host-guard.service"
      ]
      ++ optional config.sops.useSystemdActivation "sops-install-secrets.service";
      after = [
        "kaseinetover-host-guard.service"
        "sops-install-secrets.service"
      ];
    };
    "wireguard-wgverizon" = {
      partOf = [ "container@kaseinetover.service" ];
      # Migrate the old networkd-created host device on the first activation.
      # The guard is already active; on restart nspawn returns the device first.
      serviceConfig.ExecStartPre = "-${pkgs.iproute2}/bin/ip link delete dev wgverizon";
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
        "wireguard-wgverizon.service"
        "kaseinetover-host-guard.service"
        "systemd-resolved.service"
        "systemd-resolved-varlink.socket"
      ];
      after = [
        "wireguard-wgover.service"
        "wireguard-wgverizon.service"
        "kaseinetover-host-guard.service"
        "systemd-resolved.service"
        "systemd-resolved-varlink.socket"
      ];
    };
  };

  # The container's NSS resolver uses this host-side Unix socket, never its VPN.
  systemd.services.systemd-resolved.serviceConfig.RuntimeDirectoryPreserve = true;

  # Keep these rules even while the container is stopped and nspawn returns WG
  # devices to the host. This coexists with the existing iptables firewall/NAT.
  systemd.services.kaseinetover-host-guard = {
    description = "Block host access to container WireGuard interfaces";
    wantedBy = [ "multi-user.target" ];
    after = [ "sysinit.target" ];
    before = [
      "network-pre.target"
      "shutdown.target"
    ];
    wants = [
      "network-pre.target"
      "sysinit.target"
    ];
    conflicts = [ "shutdown.target" ];
    unitConfig.DefaultDependencies = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.nftables}/bin/nft -f ${overHostFirewall}";
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
      "10-kaseinetover-unmanaged" = {
        matchConfig.Name = "wgover wgverizon";
        linkConfig.Unmanaged = true;
      };
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
