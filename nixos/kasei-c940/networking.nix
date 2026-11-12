{ config, pkgs, ... }:

with pkgs.lib;
{
  systemd.network.enable = mkForce false;
  networking = {
    hostName = "kasei-c940";
    useDHCP = false;
    useNetworkd = false;
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
              oifname { enp2s0,wlo1,tinc.kaseinet,tun0,tun1 } masquerade
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

    networkmanager = {
      enable = true;
      # Use DNS servers supplied by the active connection (DHCP/IPv6 RA).
      dns = "default";
      logLevel = "INFO";
      unmanaged = [
        "interface-name:tinc.kaseinet"
      ];
      ensureProfiles = {
        environmentFiles = [ "${config.sops.secrets.networkmanager-env.path}" ];
        profiles = {
          "kaseinet" = {
            connection = {
              id = "kaseinet";
              type = "wifi";
            };
            wifi = {
              mode = "infrastructure";
              ssid = "kaseinet";
            };
            wifi-security = {
              key-mgmt = "sae";
              psk = "$kaseinet_PASSWORD";
            };
            ipv4 = {
              method = "auto";
            };
            ipv6 = {
              method = "auto";
            };
          };
          "comm" = {
            connection = {
              id = "comm";
              type = "wifi";
            };
            wifi = {
              mode = "infrastructure";
              ssid = "comm";
            };
            wifi-security = {
              key-mgmt = "wpa-psk";
              auth-alg = "open";
              psk = "$comm_PASSWORD";
            };
            ipv4 = {
              method = "auto";
            };
            ipv6 = {
              method = "auto";
            };
          };
        };
      };
    };
  };

  services.chinaRoute = {
    fwmark = 200;
    enableV4 = true;
    enableV6 = false;
  };
}
