{ config, pkgs, ... }:
{
  # tinc
  sops.secrets = {
    tinced25519 = { mode = "0400"; };
    vaultwarden = {
      mode = "0400";
      owner = config.users.users."vaultwarden".name;
    };
    cloudflared = {
      owner = config.users.users."cloudflared".name;
    };
    acme-cloudflare = {
      mode = "0400";
      owner = config.users.users."acme".name;
    };
    btrbk-sshkey = {
      mode = "0400";
      owner = config.users.users."btrbk".name;
    };
    miioenv = { };
  };

  /*
    containers."iptv" = {
    privateNetwork = true;
    hostBridge = "iptvbr";

    config = { config, pkgs, lib, ... }: {
      environment.systemPackages = with pkgs; [
        curl
        socat
        ffmpeg
      ];

      networking = {
        useNetworkd = true;
        firewall.enable = false;

        interfaces.eth0 = {
          useDHCP = true;
        };
      };

      services = {
        resolved.enable = false;
      };

      system.stateVersion = "24.04";
    };
    };
  */

  services.vaultwarden = {
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

  services.prometheus = {
    exporters.node = {
      enable = true;
      enabledCollectors = [
        "systemd"
        "interrupts"
        "softirqs"
      ];
    };
  };

  services.cloudflared = {
    enable = true;
    tunnels."71d3c820-b722-45d5-810f-7185d0c6b54c" = {
      originRequest = {
        #originServerName = "kasei.im";
      };
      ingress = {
        "bt.kasei.im" = "https://nas0.i.kasei.im:443";
        "bitwarden.kasei.im" = "https://n3160.i.kasei.im:443";
        "outline.kasei.im" = "https://nas0.i.kasei.im:443";
      };
      default = "http_status:404";
      credentialsFile = "${config.sops.secrets.cloudflared.path}";
    };
  };

  services.vlmcsd = {
    enable = true;
  };

  services.miio-exporter = {
    enable = true;
    environmentFile = "${config.sops.secrets.miioenv.path}";
  };

  security.acme = {
    acceptTerms = true;
    defaults = {
      server = "https://acme-v02.api.letsencrypt.org/directory";
      email = "kasei@kasei.im";
      dnsProvider = "cloudflare";
      dnsResolver = "127.0.0.1:53";
      credentialsFile = "${config.sops.secrets.acme-cloudflare.path}";
      reloadServices = [ "nginx" ];
    };
    certs = {
      "kasei.im" = {
        domain = "kasei.im";
        extraDomainNames = [ "*.kasei.im" "*.i.kasei.im" ];
        keyType = "ec256";
      };
    };
  };

  users.users.nginx.extraGroups = [ "acme" ];
  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedProxySettings = true;
    sslProtocols = "TLSv1.2 TLSv1.3";
    commonHttpConfig = ''
      ssl_session_tickets on;
      ssl_prefer_server_ciphers off;
      ssl_stapling on;
      ssl_stapling_verify on;
    '';
    virtualHosts =
      let
        mkVirtualHosts = input: input // {
          reuseport = true;
          onlySSL = true;
          sslCertificate = ''${config.security.acme.certs."kasei.im".directory}/full.pem'';
          sslCertificateKey = ''${config.security.acme.certs."kasei.im".directory}/full.pem'';
          extraConfig = ''
            add_header Alt-Svc 'h3=":$server_port"; ma=86400';
          '';
        };
      in
      {
        "default" = {
          serverName = "_";
          default = true;
          rejectSSL = true;
          reuseport = true;
          locations."/" = {
            return = "444";
          };
        };
        "${config.networking.hostName}.${config.networking.domain}" = mkVirtualHosts {
          locations."/" = {
            return = "200";
          };
        };
        "bitwarden.kasei.im" = mkVirtualHosts {
          serverName = "bitwarden.kasei.im";
          locations."/" = {
            proxyPass = "http://127.0.0.1:8000";
            proxyWebsockets = true;
          };
        };
        "zte.i.kasei.im" = mkVirtualHosts {
          serverName = "zte.i.kasei.im";
          locations."/" = {
            proxyPass = "http://192.168.1.1";
          };
        };
      };
  };

  services.btrfs = {
    autoScrub = {
      enable = true;
      fileSystems = [ "/mnt/bareroot" ];
      interval = "monthly";
    };
  };

  services.btrbk = {
    ioSchedulingClass = "idle";
    instances = {
      "${config.networking.hostName}" = {
        onCalendar = "hourly";
        settings = {
          snapshot_preserve = "72h";
          snapshot_preserve_min = "3h";
          target_preserve = "144h 14d 14w";
          target_preserve_min = "no";
          snapshot_dir = "_btrbk_snapshots";
          ssh_identity = "${config.sops.secrets.btrbk-sshkey.path}";
          stream_compress = "zstd";
          stream_compress_level = "1";
          stream_buffer = "128m";
          volume = {
            "/mnt/bareroot" = {
              subvolume = {
                "nixos_persist" = { };
              };
              target = "ssh://nas0.i.kasei.im/mnt/backup_disk/${config.networking.hostName}";
            };
          };
        };
      };
    };
  };

  /*
    services.udpxy = {
    enable = true;
    mcastaddr = "cmcciptv";
    binaddr = "ens1";
    };
  */
}
