{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.singbox-client;
in
{
  options.services.singbox-client = {
    enable = mkOption {
      type = types.bool;
      default = false;
    };
    localRouteMark = mkOption {
      type = types.int;
      default = 200;
    };
    sercretPath = mkOption {
      type = types.path;
    };
  };

  config = mkIf cfg.enable {
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
            listen = "::";
            listen_port = 8688;
            tag = "ss-in";
            type = "shadowsocks";
            sniff = true;
            sniff_override_destination = true;
            method = "2022-blake3-aes-128-gcm";
            password = {
              _secret = "${cfg.sercretPath}";
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
              _secret = "${cfg.sercretPath}";
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
              _secret = "${cfg.sercretPath}";
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
              _secret = "${cfg.sercretPath}";
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
              _secret = "${cfg.sercretPath}";
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
            routing_mark = cfg.localRouteMark;
          }
        ];
        route = {
          default_mark = cfg.localRouteMark;
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
                ".clngaa.com"
                ".steamcontent.com"
                ".pphimalayanrt.com"
                # kaspersky
                ".kaspersky.com"
                ".kaspersky-labs.com"
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
  };
}
