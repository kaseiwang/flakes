{ config, pkgs, ... }:
{
  sops.secrets = {
    singboxpass = { };
    cloudflared = {
      #owner = config.users.users."cloudflared".name;
    };
  };

  services = {
    cloudflared = {
      enable = true;
      tunnels."5beeeed9-80a2-4b40-92b5-b15e54fd8c7b" = {
        ingress = {
          "bitwarden.kasei.im" = "https://nas0.i.kasei.im:443";
          "grafana.kasei.im" = "https://nas0.i.kasei.im:443";
        };
        default = "http_status:404";
        credentialsFile = "${config.sops.secrets.cloudflared.path}";
      };
    };

    sing-box = {
      enable = true;
      settings = {
        dns = {
          servers = [
            {
              tag = "cloudflare";
              type = "tls";
              server = "2606:4700:4700::1111";
            }
          ];
          strategy = "prefer_ipv6";
          final = "cloudflare";
        };
        inbounds = [
          {
            listen = "::";
            listen_port = 8688;
            tag = "ss-in";
            type = "shadowsocks";
            method = "2022-blake3-aes-128-gcm";
            password = {
              _secret = "${config.sops.secrets.singboxpass.path}";
            };
            multiplex = {
              enabled = true;
            };
          }
          {
            listen = "10.10.0.21";
            listen_port = 8680;
            tag = "overwg-in";
            type = "shadowsocks";
            method = "none";
            multiplex = {
              enabled = true;
            };
          }
        ];
      };
    };

    prometheus = {
      exporters = {
        node = {
          enable = true;
          enabledCollectors = [
            "systemd"
            "ethtool"
            "interrupts"
          ];
        };
      };
    };
  };
}
