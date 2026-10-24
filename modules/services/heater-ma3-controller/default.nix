{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.heater-ma3-controller;
  python = pkgs.python314.withPackages (ps: [
    ps.python-miio
    ps.prometheus-client
  ]);
  controller = pkgs.writeText "heater-ma3-controller.py" (builtins.readFile ./controller.py);
  page = pkgs.writeText "heater-ma3.html" (builtins.readFile ./index.html);
in
{
  options.services.heater-ma3-controller = {
    enable = lib.mkEnableOption "Qingping PI room-temperature controller for the MIoT heater";
    host = lib.mkOption {
      type = lib.types.str;
      default = "10.10.5.189";
    };
    tokenFile = lib.mkOption {
      type = lib.types.path;
      description = "Runtime token file provided by sops-nix";
    };
    origin = lib.mkOption {
      type = lib.types.str;
      example = "https://nas0.i.kasei.im";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 9192;
    };
    qingpingUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:${toString config.services.qingping-miio-exporter.port}/metrics";
      description = "Local Qingping exporter endpoint, including acquisition timestamps.";
    };
    kp = lib.mkOption {
      type = lib.types.float;
      default = 0.25;
      description = "PI proportional gain, duty ratio per degree Celsius.";
    };
    ki = lib.mkOption {
      type = lib.types.float;
      default = 0.00006944444444444444;
      description = "PI integral gain, duty ratio per degree Celsius per second.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.kp >= 0 && cfg.ki >= 0;
        message = "heater-ma3-controller PI gains must be nonnegative";
      }
    ];
    systemd.services.heater-ma3-controller = {
      description = "Low-heat MIoT controller with Qingping PI feedback";
      after = [
        "network-online.target"
        "qingping-miio-exporter.service"
      ];
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
          controller
          "--host"
          cfg.host
          "--token-file"
          "%d/miio-token"
          "--state-file"
          "/var/lib/heater-ma3-controller/state.json"
          "--page"
          page
          "--origin"
          cfg.origin
          "--port"
          (toString cfg.port)
          "--qingping-url"
          cfg.qingpingUrl
          "--kp"
          (builtins.toJSON cfg.kp)
          "--ki"
          (builtins.toJSON cfg.ki)
        ];
        LoadCredential = "miio-token:${cfg.tokenFile}";
        StateDirectory = "heater-ma3-controller";
        StateDirectoryMode = "0700";
        DynamicUser = true;
        Restart = "on-failure";
        RestartSec = 5;
        TimeoutStopSec = 20;
        UMask = "0077";
        CapabilityBoundingSet = "";
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectClock = true;
        ProtectHostname = true;
        ProtectControlGroups = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        LockPersonality = true;
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
