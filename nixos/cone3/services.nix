{ config, pkgs, ... }:
{
  sops.secrets = {
    singboxpass = { };
  };

  services.sing-box = {
    enable = true;
    settings = {
      dns = {
        servers = [
          {
            tag = "cloudflare";
            address = "https://1.1.1.1/dns-query";
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
          password = { _secret = "${config.sops.secrets.singboxpass.path}"; };
          multiplex = {
            enabled = true;
          };
        }
        {
          listen = "::";
          listen_port = 443;
          tag = "tls-in";
          type = "shadowtls";
          version = 3;
          users = [
            {
              name = "singbox";
              password = { _secret = "${config.sops.secrets.singboxpass.path}"; };
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