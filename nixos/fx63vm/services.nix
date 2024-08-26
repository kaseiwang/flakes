{ config, pkgs, ... }:

{
  sops.secrets = {
    nextcloud-admin = {
      mode = "0400";
      owner = config.users.users."nextcloud".name;
    };
    miio-token = {
      mode = "0400";
    };
    nginx-basic-auth = {
      owner = config.users.users."nginx".name;
    };
    chatgpt-envs = { };
    grafana-envs = {
      owner = config.users.users."grafana".name;
    };
    zfs-key = {
      mode = "0400";
    };
  };

  systemd.services.grafana.serviceConfig.EnvironmentFile = "${config.sops.secrets.grafana-envs.path}";

  virtualisation = {
    oci-containers.containers = {
      "alist" = {
        image = "xhofe/alist:v3.36.0";
        environment = {
          PUID = "0";
          PGID = "0";
          UMASK = "022";
        };
        volumes = [
          "alist:/opt/alist/data"
          #"/pool0/samba-share:/mnt/samba"
          "/pool0/encrypted/media/samba:/mnt/samba"
          "/pool0/encrypted/media/qbittorrent/.config/qBittorrent/downloads:/mnt/qbittorrent"
        ];
        ports = [ "127.0.0.1:5244:5244" ];
      };
      "chatgpt-next-web" = {
        image = "yidadaa/chatgpt-next-web:v2.14.0";
        ports = [ "127.0.0.1:3000:3000" ];
        environmentFiles = [ "${config.sops.secrets.chatgpt-envs.path}" ];
        environment = {
          PROXY_URL = "http://10.10.2.1:1080/";
          HOSTNAME = "0.0.0.0";
        };
      };
      "peerbanhelper" = {
        image = "ghostchu/peerbanhelper:v5.1.0";
        ports = [ "127.0.0.1:9898:9898" ];
        volumes = [
          "peerbanhelper:/app/data"
          "peerbanhelper-tmpfs:/tmp"
          "/etc/localtime:/etc/localtime,read-only=true"
        ];
      };
    };
  };

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
        fileSystems = [ "/mnt/bareroot" "/mnt/backup_disk" ];
        interval = "monthly";
      };
    };

    undervolt = {
      enable = true;
      coreOffset = -70;
      p1 = {
        limit = 25;
        window = 28;
      };
      p2 = {
        limit = 35;
        window = 0.0025;
      };
    };

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
          name = "${config.services.gitea.database.name}";
          ensureDBOwnership = true;
        }
      ];
      ensureDatabases = [
        "${config.services.nextcloud.config.dbname}"
        "${config.services.gitea.database.name}"
      ];
    };

    postgresqlBackup = {
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
        /*
        nextcloud = {
          enable = true;
          url = "https://nextcloud.kasei.im";
        };
          */
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
        {
          job_name = "miio";
          static_configs = [
            { targets = [ "10.10.2.1:9191" ]; }
          ];
        }
        {
          job_name = "ntpd-rs";
          static_configs = [
            { targets = [ "10.10.2.1:9975" ]; }
          ];
        }
        {
          job_name = "nvidia_gpu";
          static_configs = [
            { targets = [ "localhost:9835" ]; }
          ];
        }
        /*
        {
          job_name = "blackbox";
          metrics_path = "/probe";
          params = { module = [ "http_2xx" ]; };
          static_configs = [
            { targets = [ "http://10.10.3.1" ]; }
          ];
        }
        */
      ];
    };

    nvidia_gpu_exporter = {
      enable = true;
    };

    redis = {
      servers = {
        "nextcloud" = {
          enable = true;
        };
      };
    };

    memcached = {
      enable = true;
      enableUnixSocket = true;
      maxMemory = 512;
    };

    nextcloud = {
      enable = true;
      package = pkgs.nextcloud29;
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

    gitea = {
      enable = true;
      database = {
        type = "postgres";
      };
      settings = {
        session.COOKIE_SECURE = true;
        server = {
          PROTOCOL = "http+unix";
          DOMAIN = "gitea.kasei.im";
          ROOT_URL = "https://gitea.kasei.im";
        };
        service = {
          DISABLE_REGISTRATION = true;
        };
      };
    };

    /*
      calibre-web = {
      enable = true;
      openFirewall = false;
      options = {
        enableBookUploading = true;
        calibreLibrary = "/pool0/media/Calibre";
      };
      };
    */

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
      configText = ''
        [global]
        workgroup = MYGROUP
        server string = NAS0 Samba Server
        security = user
        server min protocol = SMB2
        server max protocol = SMB3
        server role = standalone server
        dns proxy = no
        [nas0]
            path = /pool0/encrypted/media/samba
            valid users = @nas, kasei
            public = no
            writable = yes
            create mask = 0765
        [qbittorrent]
            path = /pool0/encrypted/media/qbittorrent/downloads
            valid users = @nas, kasei
            public = no
            force user = qbittorrent
            force group = nas
            browseable = yes
            read only = yes
      '';
    };

    samba-wsdd = {
      enable = true;
      hostname = "${config.networking.hostName}";
    };

    yarr = {
      enable = true;
      proxy = "socks5://10.10.2.1:1080";
    };

    /*
      target = {
      enable = true;
      config = {
        fabric_modules = [ ];
        storage_objects = [
          {
            dev = "/dev/zvol/pool0/iscsi/win";
            name = "nas0-win";
            plugin = "block";
            write_back = true;
            wwn = "92b17c3f-6b40-4168-b082-ceeb7b495522";
          }
        ];
        targets = [
          {
            fabric = "iscsi";
            tpgs = [
              {
                enable = true;
                attributes = {
                  authentication = 0;
                  generate_node_acls = 1;
                };
                luns = [
                  {
                    alias = "94dfe06967";
                    alua_tg_pt_gp_name = "default_tg_pt_gp";
                    index = 0;
                    storage_object = "/backstores/block/nas0-win";
                  }
                ];
                node_acls = [
                  {
                    mapped_luns = [
                      {
                        alias = "d42f5bdf8a";
                        index = 0;
                        tpg_lun = 0;
                        write_protect = false;
                      }
                    ];
                    node_wwn = "iqn.1991-05.com.microsoft:gih-d-26829";
                  }
                ];
                portals = [
                  {
                    ip_address = "0.0.0.0";
                    iser = false;
                    offload = false;
                    port = 3260;
                  }
                ];
                tag = 1;
              }
            ];
            wwn = "iqn.2003-01.org.linux-iscsi.target.x8664:sn.acf8fd9c23af";
          }
        ];
      };
      };
      */


    nginx = {
      enable = true;
      package = pkgs.nginxQuic;
      enableQuicBPF = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      recommendedGzipSettings = false;
      recommendedZstdSettings = false;
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
          mkVirtualHosts = input: input // {
            reuseport = true;
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
          "gitea.kasei.im" = mkVirtualHosts {
            serverName = "gitea.kasei.im";
            locations."/" = {
              proxyPass = "http://unix:${config.services.gitea.settings.server.HTTP_ADDR}";
              extraConfig = ''client_max_body_size 512M;'';
              proxyWebsockets = true;
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
              proxyPass = "http://localhost:${toString config.services.qbittorrent.port}";
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
      group = "nas";
      openFilesLimit = 65535;
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
      sshAccess = [{
        # public key for ssh access
        key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGYS314z/+xrO5qjNWmTDLPo9OSk+mHQYPz8J0WOYbbQ";
        roles = [ "source" "info" "target" "delete" "snapshot" "send" "receive" ];
      }];
    };
  };
}
