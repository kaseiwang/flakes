{ config, pkgs, ... }:
{
  sops.secrets = {
    inadyn = { };
  };

  services = {
    irqbalance.enable = true;

    sing-box = {
      enable = true;
      settings = {
        log = {
          level = "info";
        };
        dns = {
          servers = [
            {
              tag = "cloudflare";
              address = "https://1.1.1.1/dns-query";
              strategy = "prefer_ipv6";
            }
            {
              tag = "origin";
              address = "10.248.2.2";
              strategy = "ipv4_only";
              detour = "native";
            }
          ];
          rules = [{
            geosite = [ "cn" ];
            domain_suffix = [ ".netease.com" ".nease.net" ];
            server = "origin";
          }];
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
        ];
        outbounds = [
          {
            type = "direct";
            tag = "wgcf";
            bind_interface = "wgcf";
          }
          {
            type = "direct";
            tag = "native";
            bind_interface = "wanbr";
          }
        ];
        route = {
          rules = [
            {
              geosite = [ "cn" ];
              geoip = [ "cn" ];
              ip_cidr = [
                "192.168.0.0/16"
                "172.16.0.0/12"
                "7.0.0.0/8"
                "10.0.0.0/8"
              ];
              domain_suffix = [ ".netease.com" ".nease.net" ];
              outbound = "native";
            }
          ];
          final = "wgcf";
        };
      };
    };

    nginx = {
      enable = true;
      virtualHosts = {
        "${config.networking.hostName}.${config.networking.domain}" = {
          default = true;
          reuseport = true;
          locations = {
            "/" = {
              return = 204;
            };
          };
        };
      };
      streamConfig = ''
        server {
          listen 0.0.0.0:3389 reuseport;
          proxy_timeout 1800s;
          proxy_pass 10.10.3.11:3389;
        }
      '';
    };

    journald = {
      extraConfig = ''
        MaxRetentionSec=6week
      '';
    };

    prometheus = {
      exporters = {
        node = {
          enable = true;
          enabledCollectors = [ "systemd" "ethtool" "interrupts" ];
        };
      };
    };

    inadyn = {
      enable = true;
      configFile = "${config.sops.secrets.inadyn.path}";
    };
  };

  systemd.services.inadyn.path = [ pkgs.iproute2 ];
}
