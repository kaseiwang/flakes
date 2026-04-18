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
              type = "tls";
              server = "2606:4700:4700::1111";
              detour = "select";
            }
            {
              tag = "tencent";
              type = "tls";
              server = "120.53.53.53";
              detour = "direct";
            }
          ];
          final = "cloudflare";
        };
        inbounds = [
          {
            listen = "::";
            listen_port = 1080;
            type = "mixed";
            tag = "in";
          }
          {
            listen = "::";
            listen_port = 8688;
            type = "shadowsocks";
            tag = "ss-in";
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
            type = "shadowsocks";
            tag = "ss-cone3";
            server = "2607:f130:0:179::2f6b:52ea";
            server_port = 8688;
            method = "2022-blake3-aes-128-gcm";
            password = {
              _secret = "${cfg.sercretPath}";
            };
            multiplex = {
              enabled = true;
              protocol = "h2mux";
            };
          }
          {
            type = "shadowsocks";
            tag = "ss-cone2";
            server = "74.48.96.113";
            server_port = 8688;
            method = "2022-blake3-aes-128-gcm";
            password = {
              _secret = "${cfg.sercretPath}";
            };
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
            domain_resolver = {
              server = "tencent";
            };
            routing_mark = cfg.localRouteMark;
          }
        ];
        route = {
          default_mark = cfg.localRouteMark;
          default_domain_resolver = {
            server = "cloudflare";
          };
          rules = [
            {
              inbound = [
                "in"
                "ss-in"
              ];
              action = "sniff";
              timeout = "3s";
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
              ip_is_private = true;
              rule_set = [
                "geoip-cn"
                "geosite-cn"
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
