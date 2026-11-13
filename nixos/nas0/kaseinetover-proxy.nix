{ config, lib, ... }:
let
  cfg = config.services.kaseinetover-proxy;
  port = 12345;
in
{
  options.services.kaseinetover-proxy.domainSuffixesFile = lib.mkOption {
    type = lib.types.str;
    description = "Runtime path to a JSON array of domain suffixes routed through devbox.";
  };

  config = {
    services.sing-box = {
      enable = true;
      settings = {
        log.level = "info";
        inbounds = [
          {
            type = "redirect";
            tag = "tcp-in";
            listen = "0.0.0.0";
            listen_port = port;
          }
          {
            type = "direct";
            tag = "dns-in";
            listen = "10.10.10.1";
            listen_port = 53;
          }
        ];
        dns = {
          # Return real answers; this is only a fallback for connections without SNI.
          reverse_mapping = true;
          servers = [
            {
              type = "tcp";
              tag = "corporate";
              # This loopback address is reached by devbox's SOCKS server.
              server = "127.0.0.53";
              detour = "devbox";
            }
            {
              type = "udp";
              tag = "public";
              server = "1.1.1.1";
              bind_interface = "wgover";
              inet4_bind_address = "10.10.10.1";
            }
          ];
          rules = [
            {
              domain_suffix = {
                _secret = cfg.domainSuffixesFile;
                quote = false;
              };
              action = "route";
              server = "corporate";
            }
          ];
          final = "public";
        };
        outbounds = [
          {
            type = "socks";
            tag = "devbox";
            server = "10.203.1.2";
            server_port = 1081;
            version = "5";
            network = "tcp";
            bind_interface = "wgover";
            inet4_bind_address = "10.203.0.1";
          }
          {
            type = "direct";
            tag = "cone3";
            bind_interface = "wgover";
            # cone3 admits/NATs the Wi-Fi subnet, not the tunnel source address.
            inet4_bind_address = "10.10.10.1";
          }
        ];
        route = {
          default_domain_resolver = "public";
          rules = [
            {
              inbound = [ "dns-in" ];
              action = "hijack-dns";
            }
            {
              inbound = [ "tcp-in" ];
              action = "sniff";
              sniffer = [
                "http"
                "tls"
              ];
              timeout = "1s";
            }
            {
              domain_suffix = {
                _secret = cfg.domainSuffixesFile;
                quote = false;
              };
              action = "route";
              outbound = "devbox";
            }
          ];
          # No automatic fallback from devbox to the public exit.
          final = "cone3";
        };
      };
    };

    systemd.services.sing-box = {
      requires = [
        "nftables.service"
        "systemd-networkd.service"
      ];
      after = [
        "nftables.service"
        "systemd-networkd.service"
      ];
      # networkd starting does not imply that the listening address exists yet.
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = "2s";
      };
      unitConfig.StartLimitIntervalSec = 0;
    };

    networking.nftables = {
      enable = true;
      ruleset = ''
        table inet over_filter {
          chain input {
            type filter hook input priority filter; policy drop;
            iifname "lo" accept
            ct state invalid drop
            ct state established,related accept
            # DHCP discovery can have source 0.0.0.0.
            iifname "over10" udp sport 68 udp dport 67 accept
            iifname "over10" ip saddr 10.10.10.0/24 meta l4proto { tcp, udp } th dport 53 accept
            iifname "over10" ip saddr 10.10.10.0/24 ct status dnat tcp dport ${toString port} accept
            iifname "over10" ip saddr 10.10.10.0/24 ip protocol icmp accept
          }
          chain forward {
            type filter hook forward priority filter; policy drop;
            ct state invalid drop
            # Clients must use the proxy, not address other tunnel peers directly.
            iifname "over10" ip daddr { 10.203.0.0/30, 10.203.1.2 } drop
            iifname "over10" oifname "wgover" ip saddr 10.10.10.0/24 accept
            iifname "wgover" oifname "over10" ip daddr 10.10.10.0/24 ct state established,related accept
          }
          chain mss_in {
            type filter hook prerouting priority mangle; policy accept;
            iifname "over10" ip saddr 10.10.10.0/24 tcp flags & (syn | rst) == syn tcp option maxseg size > 1340 tcp option maxseg size set 1340
          }
          chain mss_out {
            type filter hook output priority mangle; policy accept;
            oifname { "over10", "wgover" } meta nfproto ipv4 tcp flags & (syn | rst) == syn tcp option maxseg size > 1340 tcp option maxseg size set 1340
          }
        }
        table ip over_nat {
          chain tcp_proxy {
            fib daddr type local return
            # Do not bypass RFC1918: corporate domains can resolve to private IPs.
            ip daddr { 0.0.0.0/8, 10.10.10.0/24, 10.203.0.0/30, 10.203.1.2, 127.0.0.0/8, 169.254.0.0/16, 224.0.0.0/4, 240.0.0.0/4 } return
            meta l4proto tcp redirect to :${toString port}
          }
          chain prerouting {
            type nat hook prerouting priority dstnat; policy accept;
            # Also catch clients still using the previous DHCP DNS addresses.
            iifname "over10" ip saddr 10.10.10.0/24 meta l4proto { tcp, udp } th dport 53 redirect to :53
            iifname "over10" ip saddr 10.10.10.0/24 meta l4proto tcp jump tcp_proxy
          }
        }
      '';
    };
  };
}
