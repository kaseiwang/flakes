{ config, ... }:

{
  networking = {
    hostName = "kasei-c940";
    useDHCP = false;
    useNetworkd = true;
    firewall.enable = false;
    nftables = {
      enable = true;
      tables = {
        mangle = {
          family = "inet";
          content = ''
            set kaseiserversv4 {
              type ipv4_addr
              flags constant,interval
              elements = {
                7.0.0.0/8,
                10.0.0.0/8,
                172.16.0.0/12,
                192.168.0.0/16,
                163.47.135.141/32, # cone
              }
            }

            set localnetv6 {
              type ipv6_addr
              flags constant, interval
              elements = {
                fc00::/7
              }
            }

            chain prerouting {
              type filter hook prerouting priority mangle + 10;
              jump route-mark;
            }

            chain output {
              type route hook output priority mangle + 10; policy accept;
              jump route-mark;
              #meta mark != 200-300 counter;
            }

            chain route-mark {
              ip daddr @kaseiserversv4 meta mark set 200;
              ip6 daddr @localnetv6 meta mark set 200
              meta mark != 200 meta mark set 300;
              meta mark 200;
              meta mark 300;
            }
          '';
        };
        filter = {
          family = "inet";
          content = ''
            chain input {
              type filter hook input priority filter; policy drop;

              meta l4proto icmp accept comment "Accept ICMP"
              meta l4proto icmpv6 accept comment "Accept ICMPv6"
              ip protocol igmp accept comment "Accept IGMP"

              tcp dport { 22, 655, 3690, 8080} accept;
              udp dport { 22, 655} accept;
              # DHCP replies for networkd on wired and wireless uplinks.
              udp sport 67 udp dport 68 accept;
              udp sport 547 udp dport 546 accept;

              # Allow trusted networks to access the router
              iifname {lo, docker0, tinc.kaseinet} accept;

              # Allow returning traffic from ppp0 and drop everthing else
              ct state established,related accept;
              iifname "ppp0" drop
            }

            chain forward {
              type filter hook forward priority filter; policy drop;

              iifname "docker0" accept
              ct state established,related accept
            }

            chain output {
              type filter hook output priority filter; policy accept;
              tcp flags syn tcp option maxseg size set rt mtu
            }
          '';
        };
        nat = {
          family = "ip";
          content = ''
            chain prerouting {
              type nat hook output priority 100; policy accept;
            }

            chain postrouting {
              type nat hook postrouting priority 100; policy accept;
              oifname { enp2s0,tinc.kaseinet,tun0,tun1 } masquerade
              oifname "wl*" masquerade
            }
          '';
        };
        nat6 = {
          family = "ip6";
          content = ''
            chain prerouting {
              type nat hook output priority 100; policy accept;
            }

            chain postrouting {
              type nat hook postrouting priority 100; policy accept;
            }
          '';
        };
      };
    };

    networkmanager.enable = false;
    wireless.iwd = {
      enable = true;
      settings.General.EnableNetworkConfiguration = false;
    };
  };

  services.chinaRoute = {
    fwmark = 200;
    enableV4 = true;
    enableV6 = false;
  };

  services.resolved.enable = true;

  systemd.network = {
    enable = true;
    # Either wired or wireless connectivity is sufficient for this desktop.
    wait-online.enable = false;
    networks = {
      "20-wired" = {
        matchConfig = {
          Type = "ether";
          # Only physical devices; leave Docker, tinc and VPN links alone.
          Path = "*";
        };
        networkConfig = {
          DHCP = "yes";
          IPv6AcceptRA = true;
        };
        dhcpV4Config.RouteMetric = 100;
        ipv6AcceptRAConfig.RouteMetric = 100;
      };
      "25-wifi-kaseinetover" = {
        matchConfig = {
          Type = "wlan";
          SSID = "kaseinetover";
        };
        networkConfig = {
          DHCP = "ipv4";
          IPv6AcceptRA = false;
          LinkLocalAddressing = "no";
        };
        dhcpV4Config.RouteMetric = 600;
      };
      "30-wifi" = {
        matchConfig.Type = "wlan";
        networkConfig = {
          DHCP = "yes";
          IPv6AcceptRA = true;
        };
        dhcpV4Config.RouteMetric = 600;
        ipv6AcceptRAConfig.RouteMetric = 600;
      };
    };
  };

  # Seed writable iwd profiles from SOPS; C preserves existing local profiles.
  systemd.tmpfiles.settings."10-iwd" = {
    "/var/lib/iwd".d.mode = "0700";
    "/var/lib/iwd/kaseinetover.psk".C = {
      mode = "0600";
      argument = config.sops.secrets."wireless/kaseinetover".path;
    };
    "/var/lib/iwd/kaseinet.psk".C = {
      mode = "0600";
      argument = config.sops.secrets."wireless/kaseinet".path;
    };
    "/var/lib/iwd/comm.psk".C = {
      mode = "0600";
      argument = config.sops.secrets."wireless/comm".path;
    };
  };
}
