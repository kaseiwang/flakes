{ config, lib, ... }:
let
  cfg = config.services.kaseinetover-tcp-proxy;
  port = 12345;
in
{
  options.services.kaseinetover-tcp-proxy.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Split forwarded TCP connections inside the kaseinetover container.";
  };

  config = {
    services.sing-box = lib.mkIf cfg.enable {
      enable = true;
      settings = {
        inbounds = [
          {
            type = "redirect";
            tag = "tcp-in";
            listen = "0.0.0.0";
            listen_port = port;
          }
        ];
        outbounds = [
          {
            type = "direct";
            tag = "verizon";
            bind_interface = "wgverizon";
          }
        ];
        # Use the original destination IP; no sniffing or DNS rewriting.
        route.final = "verizon";
      };
    };

    systemd.services.sing-box = lib.mkIf cfg.enable {
      requires = [
        "nftables.service"
        "systemd-networkd.service"
      ];
      after = [
        "nftables.service"
        "systemd-networkd.service"
      ];
    };

    # Disabling the proxy restores the original forwarding and NAT path.
    networking.nftables = {
      enable = true;
      ruleset = ''
        table inet over_filter {
          chain input {
            type filter hook input priority filter; policy drop;
            iifname "lo" accept
            ${lib.optionalString cfg.enable ''
              ct state invalid drop
              iifname { "wgover", "wgverizon" } ct state established,related accept
              iifname "wgover" ip saddr 10.10.10.0/24 ct status dnat tcp dport ${toString port} accept
            ''}
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
          ${lib.optionalString cfg.enable ''
            # Redirected TCP no longer traverses the forward hook.
            chain proxy_mss_in {
              type filter hook prerouting priority mangle; policy accept;
              iifname "wgover" ip saddr 10.10.10.0/24 tcp flags & (syn | rst) == syn tcp option maxseg size > 1340 tcp option maxseg size set 1340
            }
            chain proxy_mss_out {
              type filter hook output priority mangle; policy accept;
              oifname { "wgover", "wgverizon" } meta nfproto ipv4 tcp flags & (syn | rst) == syn tcp option maxseg size > 1340 tcp option maxseg size set 1340
            }
          ''}
        }
        table ip over_nat {
          ${lib.optionalString cfg.enable ''
            chain tcp_proxy {
              # Keep local and private destinations on the existing path.
              fib daddr type local return
              ip daddr { 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 240.0.0.0/4 } return
              meta l4proto tcp counter redirect to :${toString port}
            }
            chain prerouting {
              type nat hook prerouting priority dstnat; policy accept;
              iifname "wgover" ip saddr 10.10.10.0/24 meta l4proto tcp jump tcp_proxy
            }
          ''}
          chain postrouting {
            type nat hook postrouting priority srcnat; policy accept;
            oifname "wgverizon" ip saddr 10.10.10.0/24 snat to 10.7.0.2
          }
        }
      '';
    };
  };
}
