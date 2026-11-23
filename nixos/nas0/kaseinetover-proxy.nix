{ config, lib, ... }:
let
  cfg = config.services.kaseinetover-proxy;
  port = 12345;
  lanRanges = lib.concatStringsSep ", " cfg.internalNetworks;
  # The host can originate traffic from its directly connected overlan address.
  internalAddresses = lib.concatStringsSep ", " (cfg.internalNetworks ++ [ "10.203.2.1/32" ]);
in
{
  options.services.kaseinetover-proxy.internalNetworks = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    description = "IPv4 LAN networks routed through nas0, bypassing the public proxy.";
  };
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
          set internal_v4 {
            type ipv4_addr; flags interval;
            elements = { ${internalAddresses} }
          }
          chain input {
            type filter hook input priority filter; policy drop;
            iifname "lo" accept
            ct state invalid drop
            ct state established,related accept
            # DHCP discovery can have source 0.0.0.0.
            iifname "over10" udp sport 68 udp dport 67 accept
            iifname "over10" ip saddr 10.10.10.0/24 meta l4proto { tcp, udp } th dport 53 accept
            iifname "over10" ip saddr 10.10.10.0/24 ct status dnat tcp dport ${toString port} accept
            iifname "over10" ip saddr 10.10.10.0/24 ip daddr @internal_v4 accept
            iifname { "overlan", "wgover" } ip saddr @internal_v4 ip daddr @internal_v4 accept
          }
          chain forward {
            type filter hook forward priority filter; policy drop;
            ct state invalid drop
            # Only private-to-private forwarding is allowed on the host link.
            iifname "overlan" oifname "wgover" ip saddr { ${lanRanges} } ip daddr 10.203.1.2 accept
            iifname "wgover" oifname "overlan" ip saddr 10.203.1.2 ip daddr { ${lanRanges} } accept
            iifname "over10" oifname "overlan" ip saddr 10.10.10.0/24 ip daddr @internal_v4 accept
            iifname "overlan" oifname "over10" ip saddr @internal_v4 ip daddr 10.10.10.0/24 accept
            iifname "over10" oifname "wgover" ip saddr 10.10.10.0/24 accept
            iifname "wgover" oifname "over10" ip saddr @internal_v4 ip daddr 10.10.10.0/24 accept
            iifname "wgover" oifname "over10" ip daddr 10.10.10.0/24 ct state established,related accept
          }
          chain output {
            type filter hook output priority filter; policy drop;
            oifname "lo" accept
            oifname "wgover" meta nfproto ipv4 accept
            oifname "over10" ip daddr 10.10.10.0/24 accept
            oifname "over10" udp sport 67 udp dport 68 accept
            oifname "overlan" ip saddr @internal_v4 ip daddr @internal_v4 accept
          }
          chain mss_in {
            type filter hook prerouting priority mangle; policy accept;
            iifname "over10" ip saddr 10.10.10.0/24 tcp flags & (syn | rst) == syn tcp option maxseg size > 1340 tcp option maxseg size set 1340
          }
          chain mss_out {
            type filter hook output priority mangle; policy accept;
            oifname { "over10", "overlan", "wgover" } meta nfproto ipv4 tcp flags & (syn | rst) == syn tcp option maxseg size > 1340 tcp option maxseg size set 1340
          }
        }
        table ip over_nat {
          chain tcp_proxy {
            fib daddr type local return
            ip daddr { ${internalAddresses} } return
            ip daddr { 0.0.0.0/8, 127.0.0.0/8, 169.254.0.0/16, 224.0.0.0/4, 240.0.0.0/4 } return
            meta l4proto tcp redirect to :${toString port}
          }
          chain prerouting {
            type nat hook prerouting priority dstnat; policy accept;
            # LAN DNS servers remain directly reachable; public DNS keeps the
            # existing interception and domain-selected wgover egress.
            ip daddr { ${internalAddresses} } return
            iifname "over10" ip saddr 10.10.10.0/24 meta l4proto { tcp, udp } th dport 53 redirect to :53
            iifname "over10" ip saddr 10.10.10.0/24 meta l4proto tcp jump tcp_proxy
          }
        }
      '';
    };
  };
}
