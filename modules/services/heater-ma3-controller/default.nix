{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.heater-ma3-controller;
  python = pkgs.python314.withPackages (ps: [ ps.python-miio ]);
  controller = pkgs.writeText "heater-ma3-controller.py" (builtins.readFile ./controller.py);
  page = pkgs.writeText "heater-ma3.html" (builtins.readFile ./index.html);
in
{
  options.services.heater-ma3-controller = {
    enable = lib.mkEnableOption "MIoT heater web controller and internal scheduler";
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
  };

  config = lib.mkIf cfg.enable {
    systemd.services.heater-ma3-controller = {
      description = "MIoT heater controller with internal 30-minute cycle";
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
