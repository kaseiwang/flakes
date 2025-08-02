{ config, pkgs, ... }:
{
  sops.secrets = {
    singboxpass = { };
  };

  services.nginx = {
    enable = true;
    virtualHosts = {
      "dcdn-origin2-test.kasei.im" = {
        default = true;
        reuseport = true;
        locations = {
          "/" = {
            return = 200;
          };
        };
      };
    };
  };

  services.sing-box = {
    enable = true;
    settings = {
      dns = {
        servers = [
          {
            tag = "cloudflare";
            address = "https://[2606:4700:4700::1111]/dns-query";
            strategy = "prefer_ipv6";
          }
        ];
        final = "cloudflare";
      };
      inbounds = [
        {
          listen = "::";
          listen_port = 9555;
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
          listen = "::";
          listen_port = 443;
          tag = "tls-in";
          type = "shadowtls";
          detour = "ss-in";
          version = 3;
          users = [
            {
              name = "singbox";
              password = {
                _secret = "${config.sops.secrets.singboxpass.path}";
              };
            }
          ];
          handshake = {
            server = "kasei.im";
            server_port = 443;
          };
        }
      ];
    };
  };
}
