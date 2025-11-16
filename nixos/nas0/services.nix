{ config, pkgs, ... }:

{
  sops.secrets = {
    nextcloud-admin = {
      owner = config.users.users."nextcloud".name;
    };
    miio-token = { };
    nginx-basic-auth = {
      owner = config.users.users."nginx".name;
    };
    chatgpt-envs = { };
    grafana-envs = {
      owner = config.users.users."grafana".name;
    };
    zfs-key = { };
    cloudflared = { };
  };

  systemd.services.grafana.serviceConfig.EnvironmentFile = "${config.sops.secrets.grafana-envs.path}";

  services = {
    zfs = {
      autoScrub = {
        enable = true;
        interval = "monthly";
      };
    };

    btrfs = {
      autoScrub = {
        enable = true;
        fileSystems = [
          "/mnt/bareroot"
          "/mnt/backup_disk"
        ];
        interval = "monthly";
      };
    };

    #undervolt = {
    #  enable = true;
    #  coreOffset = -70;
    #  p1 = {
    #    limit = 25;
    #    window = 28;
    #  };
    #  p2 = {
    #    limit = 35;
    #    window = 0.0025;
    #  };
    #};

    postgresql = {
      enable = true;
      enableTCPIP = true;
      enableJIT = true;
      dataDir = "/pool0/encrypted/postgresql/${config.services.postgresql.package.psqlSchema}";
      ensureUsers = [
        {
          name = "${config.services.nextcloud.config.dbuser}";
          ensureDBOwnership = true;
        }
        {
          name = "yarr";
          ensureDBOwnership = true;
        }
      ];
      ensureDatabases = [
        "${config.services.nextcloud.config.dbname}"
        "yarr"
      ];
    };

    postgresqlBackup = {
      startAt = "*-*-* 04:30:00"; # every day
      location = "/var/lib/backup/postgresql";
      enable = true;
      compression = "zstd";
    };

    prometheus = {
      enable = true;
      webExternalUrl = "https://${config.networking.hostName}.${config.networking.domain}/prometheus";
      globalConfig = {
        scrape_interval = "15s";
        evaluation_interval = "15s";
      };
      exporters = {
        node = {
          enable = true;
          enabledCollectors = [
            "systemd"
            "interrupts"
            "softirqs"
          ];
        };
        zfs.enable = true;
        postgres.enable = true;
        smartctl = {
          enable = true;
          devices = [
            "/dev/sda"
            "/dev/sdb"
            "/dev/sdc"
            "/dev/sdd"
          ];
        };
      };
      scrapeConfigs = [
        {
          job_name = "node";
          static_configs = [
            {
              targets = [
                "localhost:${toString config.services.prometheus.exporters.node.port}"
                "10.10.3.1:${toString config.services.prometheus.exporters.node.port}"
                "10.10.2.1:${toString config.services.prometheus.exporters.node.port}"
              ];
            }
          ];
        }
        {
          job_name = "zfs";
          static_configs = [
            { targets = [ "localhost:${toString config.services.prometheus.exporters.zfs.port}" ]; }
          ];
        }
        {
          job_name = "smartctl";
          static_configs = [
            { targets = [ "localhost:${toString config.services.prometheus.exporters.smartctl.port}" ]; }
          ];
        }
        #{
        #  job_name = "miio";
        #  static_configs = [
        #    { targets = [ "10.10.2.1:9191" ]; }
        #  ];
        #}
        {
          job_name = "ntpd-rs";
          static_configs = [
            { targets = [ "10.10.2.1:9975" ]; }
          ];
        }
      ];
    };

    redis = {
      servers = {
        "nextcloud" = {
          enable = true;
        };
      };
    };

    nextcloud = {
      enable = true;
      package = pkgs.nextcloud32;
      home = "/pool0/encrypted/nextcloud";
      hostName = "nextcloud.kasei.im";
      https = true;
      maxUploadSize = "16G";

      database.createLocally = true;
      appstoreEnable = true;
      config = {
        adminuser = "admin";
        adminpassFile = "${config.sops.secrets.nextcloud-admin.path}";

        dbtype = "pgsql";
        dbuser = "nextcloud";
        dbname = "nextcloud";
      };

      settings = {
        defaultPhoneRegion = "CN";
        overwriteProtocol = "https";
        maintenance_window_start = "1";
        logType = "file";
        logLevel = 1; # info
      };

      notify_push = {
        enable = false;
        logLevel = "info";
      };

      caching = {
        redis = true;
        apcu = true;
      };
    };

    grafana = {
      enable = true;
      settings = {
        server = {
          protocol = "socket";
          domain = "grafana.kasei.im";
          root_url = "https://grafana.kasei.im";
        };
        users = {
          allow_sign_up = false;
        };
      };
      provision = {
        datasources.settings = {
          apiVersion = 1;
          deleteDatasources = [
            {
              name = "prometheus-nas0";
              orgId = 1;
            }
          ];
          datasources = [
            {
              name = "prometheus-nas0";
              type = "prometheus";
              access = "proxy";
              orgId = 1;
              uid = "cf6dec8c-44e1-4188-a19c-d535c9e966cc";
              url = "https://nas0.i.kasei.im/prometheus";
              basicAuth = true;
              basicAuthUser = "kasei";
              isDefault = true;
              jsonData = {
                httpMethod = "POST";
                prometheusType = "Prometheus";
                manageAlerts = true;
              };
              secureJsonData = {
                basicAuthPassword = "$ENV_BASIC_AUTH_TOKEN";
              };
              editable = false;
            }
          ];
        };
        dashboards.settings = {
          apiVersion = 1;
          providers = [
            {
              name = "default";
              options.path = "/var/lib/grafana/dashboards";
            }
          ];
        };
      };
    };

    samba = {
      enable = true;
      openFirewall = true;
      settings = {
        global = {
          "server string" = "NAS0 Samba Server";
          security = "user";
          "server role" = "standalone server";
          "server min protocol" = "SMB2";
        };
        nas0 = {
          path = "/pool0/encrypted/media/samba";
          "valid users" = "@nas, kasei";
          public = "no";
          writable = "yes";
          "create mask" = "0765";
        };
        qbittorrent = {
          path = "/pool0/encrypted/media/qbittorrent/downloads";
          "valid users" = "@nas, kasei";
          public = "no";
          "force user" = "qbittorrent";
          "force group" = "nas";
          "read only" = "yes";
          "browseable" = "yes";
        };
      };
    };

    samba-wsdd = {
      enable = true;
      hostname = "${config.networking.hostName}";
    };

    yarr = {
      enable = true;
    };

    vlmcsd = {
      enable = true;
    };

    cloudflared = {
      enable = true;
      tunnels."71d3c820-b722-45d5-810f-7185d0c6b54c" = {
        originRequest = {
          #originServerName = "kasei.im";
        };
        ingress = {
          "grafana.kasei.im" = "https://nas0.i.kasei.im:443";
        };
        default = "http_status:404";
        credentialsFile = "${config.sops.secrets.cloudflared.path}";
      };
    };

    nginx = {
      enable = true;
      package = pkgs.nginxQuic;
      enableQuicBPF = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      recommendedGzipSettings = false;
      sslProtocols = "TLSv1.2 TLSv1.3";
      appendConfig = ''
        worker_processes auto;
      '';
      commonHttpConfig = ''
        ssl_session_tickets on;
        ssl_prefer_server_ciphers off;
        ssl_stapling on;
        ssl_stapling_verify on;
      '';
      virtualHosts =
        let
          mkVirtualHosts =
            input:
            input
            // {
              quic = true;
              http3 = true;
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
            serverName = "${config.networking.hostName}.${config.networking.domain}";
            basicAuthFile = "${config.sops.secrets.nginx-basic-auth.path}";
            locations = {
              "~ ^/prometheus" = {
                proxyPass = "http://localhost:${toString config.services.prometheus.port}";
              };
              "~ ^/peerbanhelper" = {
                extraConfig = ''
                  rewrite /peerbanhelper/(.*) /$1 break;
                '';
                proxyPass = "http://localhost:9898";
              };
              "/" = {
                return = 404;
              };
            };
          };
          "nextcloud.kasei.im" = mkVirtualHosts {
            serverName = "nextcloud.kasei.im";
          };
          "grafana.kasei.im" = mkVirtualHosts {
            serverName = "grafana.kasei.im";
            locations."/" = {
              proxyPass = "http://unix:${config.services.grafana.settings.server.socket}";
              proxyWebsockets = true;
            };
          };
          "bt.kasei.im" = mkVirtualHosts {
            serverName = "bt.kasei.im";
            basicAuthFile = "${config.sops.secrets.nginx-basic-auth.path}";
            locations."/" = {
              proxyPass = "http://localhost:${toString config.services.qbittorrent.webuiPort}";
              extraConfig = ''proxy_cookie_path / "/; Secure";'';
            };
          };
          "alist.kasei.im" = mkVirtualHosts {
            serverName = "alist.kasei.im";
            locations."/" = {
              proxyPass = "http://localhost:5244";
            };
          };
          "chat.kasei.im" = mkVirtualHosts {
            serverName = "chat.kasei.im";
            locations."/" = {
              proxyPass = "http://localhost:3000";
            };
          };
          "peerbanhelper.kasei.im" = mkVirtualHosts {
            serverName = "peerbanhelper.kasei.im";
            locations."/" = {
              proxyPass = "http://localhost:9898";
            };
          };
          "yarr.kasei.im" = mkVirtualHosts {
            serverName = "yarr.kasei.im";
            basicAuthFile = "${config.sops.secrets.nginx-basic-auth.path}";
            locations."/" = {
              proxyPass = "http://localhost:${toString config.services.yarr.port}";
            };
          };
        };
    };

    qbittorrent = {
      enable = true;
      package = pkgs.qbittorrent-enhanced-nox;
      group = "nas";
      profileDir = "/var/lib/qbittorrent/.config";
      #openFilesLimit = 65535;
      # TODO: use module to manage qbittorrent settings
      #dataDir = "/pool0/media/qbittorrent";
    };

    btrbk = {
      ioSchedulingClass = "idle";
      instances = {
        "nas0" = {
          onCalendar = "hourly";
          settings = {
            snapshot_preserve = "3h";
            snapshot_preserve_min = "3h";
            target_preserve = "144h 14d 14w";
            target_preserve_min = "no";
            snapshot_dir = "_btrbk_snapshots";
            volume = {
              "/mnt/bareroot" = {
                subvolume = {
                  "nixos_persist" = { };
                };
                target = "/mnt/backup_disk/nas0";
              };
            };
          };
        };
      };
      sshAccess = [
        {
          # public key for ssh access
          key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGYS314z/+xrO5qjNWmTDLPo9OSk+mHQYPz8J0WOYbbQ";
          roles = [
            "source"
            "info"
            "target"
            "delete"
            "snapshot"
            "send"
            "receive"
          ];
        }
      ];
    };
  };
}
