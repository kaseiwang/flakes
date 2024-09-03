{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.yarr;
  configDir = "${cfg.dataDir}/.config";
in
{
  options.services.yarr = {
    enable = mkOption {
      type = types.bool;
      default = false;
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/yarr";
    };

    user = mkOption {
      type = types.str;
      default = "yarr";
    };

    group = mkOption {
      type = types.str;
      default = "yarr";
    };

    addr = mkOption {
      type = types.str;
      default = "127.0.0.1";
    };

    port = mkOption {
      type = types.port;
      default = 7070;
    };

    pguri = mkOption {
      type = types.str;
      default = "";
    };

    proxy = mkOption {
      type = types.nullOr types.str;
      default = null;
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
    };
  };

  config = mkIf cfg.enable {

    environment.systemPackages = [ pkgs.yarr ];

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.port ];
    };

    systemd.services.yarr = {
      after = [ "network.target" ];
      description = "yet another rss reader";
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.yarr ];
      environment = {
        HOME = "${cfg.dataDir}";
      } // optionalAttrs (cfg.proxy != null) {
        HTTP_PROXY = cfg.proxy;
        HTTPS_PROXY = cfg.proxy;
      };
      serviceConfig = {
        ExecStart = ''
          ${pkgs.yarr}/bin/yarr \
            -addr ${cfg.addr}:${toString cfg.port}
        '';
        User = cfg.user;
        Group = cfg.group;
        StateDirectory = "yarr";
        MemoryMax = "300M";
        DynamicUser = true;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        PrivateUsers = true;
        PrivateDevices = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectProc = "invisible";
        ProtectHome = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        CapabilityBoundingSet = "";
        ProtectHostname = true;
        ProcSubset = "pid";
        SystemCallArchitectures = "native";
        UMask = "0077";
        SystemCallFilter = "@system-service";
        SystemCallErrorNumber = "EPERM";
        Restart = "always";
      };
    };

    users.users = mkIf (cfg.user == "yarr") {
      yarr = {
        group = cfg.group;
        home = cfg.dataDir;
        createHome = true;
        isSystemUser = true;
        description = "yarr Daemon user";
      };
    };

    users.groups =
      mkIf (cfg.group == "yarr") { yarr = { gid = null; }; };
  };
}
