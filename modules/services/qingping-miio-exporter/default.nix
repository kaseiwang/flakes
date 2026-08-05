{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.qingping-miio-exporter;
  exporter = pkgs.writeText "qingping-miio-exporter.py" (builtins.readFile ./exporter.py);
  python = pkgs.python314.withPackages (
    ps: with ps; [
      prometheus-client
      python-miio
    ]
  );
in
{
  options.services.qingping-miio-exporter = {
    enable = lib.mkEnableOption "Qingping Air Monitor Lite Prometheus exporter";

    host = lib.mkOption {
      type = lib.types.str;
      example = "10.10.2.164";
      description = "IP address or hostname of the Qingping device.";
    };

    tokenFile = lib.mkOption {
      type = lib.types.str;
      example = "/run/secrets/qingping-miio-token";
      description = "File containing the 32-character miIO token.";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address on which the Prometheus endpoint listens.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9191;
      description = "Port on which the Prometheus endpoint listens.";
    };

    pollInterval = lib.mkOption {
      type = lib.types.ints.positive;
      default = 15;
      description = "Seconds between device polls.";
    };

    timeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 5;
      description = "Timeout in seconds for one device request.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.timeout < cfg.pollInterval;
        message = "services.qingping-miio-exporter.timeout must be less than pollInterval";
      }
    ];

    systemd.services.qingping-miio-exporter = {
      description = "Qingping Air Monitor Lite Prometheus exporter";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        PYTHONDONTWRITEBYTECODE = "1";
        PYTHONUNBUFFERED = "1";
      };
      serviceConfig = {
        Type = "simple";
        ExecStart = lib.escapeShellArgs [
          "${python}/bin/python"
          exporter
          "--host"
          cfg.host
          "--token-file"
          "%d/miio-token"
          "--listen-address"
          cfg.listenAddress
          "--port"
          (toString cfg.port)
          "--poll-interval"
          (toString cfg.pollInterval)
          "--timeout"
          (toString cfg.timeout)
        ];
        LoadCredential = "miio-token:${cfg.tokenFile}";
        DynamicUser = true;
        Restart = "on-failure";
        RestartSec = 5;
        UMask = "0077";

        CapabilityBoundingSet = "";
        LockPersonality = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
      };
    };
  };
}
