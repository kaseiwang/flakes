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
                74.48.96.113/32, # cone
                66.103.210.62/32, # cone
                81.71.146.69/32, # gz2
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
              key-mgmt = "wpa-psk";
              auth-alg = "open";
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

  services.smartdns = {
    enable = true;
    settings = {
      bind = "[::]:53";
      bind-tcp = "[::]:53";
      cache-size = 32768; # 16MB
      cache-persist = false;
      #resolv-hostname = true;
      prefetch-domain = false;
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
      # smartdns does not read SAN, use CN
      server-tls = [
        "1.1.1.1 -tls-host-verify cloudflare-dns.com"
        "1.0.0.1 -tls-host-verify cloudflare-dns.com"
        "1.12.12.12 -tls-host-verify 120.53.53.53 -group china -exclude-default-group"
        "120.53.53.53 -tls-host-verify 120.53.53.53 -group china -exclude-default-group"
        #"223.5.5.5 -tls-host-verify *.alidns.com -group china -exclude-default-group"
        #"223.6.6.6 -tls-host-verify *.alidns.com -group china -exclude-default-group"
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
          listen = "127.0.0.1";
          listen_port = 1080;
          sniff = true;
          sniff_override_destination = true;
        }
        {
          type = "mixed";
          tag = "inbound";
          listen = "::1";
          listen_port = 1080;
          sniff = true;
          sniff_override_destination = true;
        }
      ];
      outbounds = [
        {
          type = "shadowsocks";
          tag = "ss-cone3";
          server = "66.103.210.62";
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
        }
      ];

      route = {
        default_mark = 200;
        final = "direct";
        rules = [
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
      };
    };
  };
}
