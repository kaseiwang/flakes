{ config, pkgs, ... }:
{
  services.kaseinet = {
    enable = true;
    name = "gz1";
    v4addr = "10.10.0.11";
    v6addr = "fdcd:ad38:cdc5:0::11";
    ed25519PrivateKeyFile = "${config.sops.secrets.tinced25519.path}";
  };

  services.nginx = {
    enable = true;

    virtualHosts = {
      "dcdn-origin1-test.kasei.im" = {
        listen = [
          {
            addr = "0.0.0.0";
            port = 20080;
          }
        ];
        default = true;
        reuseport = true;
        locations = {
          "/" = {
            return = 200;
          };
        };
      };
    };
    streamConfig = ''
      server {
        listen 0.0.0.0:9555 reuseport;
        proxy_timeout 1800s;
        proxy_pass 10.10.2.1:9555;
      }
    '';
  };
}
