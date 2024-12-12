{ config, pkgs, ... }:
{
  sops.secrets = {
    inadyn = { };
  };

  services = {
    irqbalance.enable = true;

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
