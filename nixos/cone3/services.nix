{ config, pkgs, ... }:
{
  sops.secrets = {
    singboxpass = { };
    vaultwarden = {
      owner = config.users.users."vaultwarden".name;
    };
  };

  services = {
    cloudflared = {
      enable = true;
      tunnels."5beeeed9-80a2-4b40-92b5-b15e54fd8c7b" = {
        ingress = {
          "bitwarden.kasei.im" = "http://127.0.0.1:8000";
        };
        default = "http_status:404";
        credentialsFile = "${config.sops.secrets.cloudflared.path}";
      };
    };

    vaultwarden = {
      enable = true;
      dbBackend = "sqlite";
      environmentFile = "${config.sops.secrets.vaultwarden.path}";
      config = {
        domain = "https://bitwarden.kasei.im/";
        signupsAllowed = false;
        webVaultEnabled = true;
        websocketEnabled = false;
      };
    };

    sing-box = {
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
            detour = "ss-in";
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
  };
}
