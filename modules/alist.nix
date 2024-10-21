{ config, lib, pkgs, utils, ... }:
with lib;
let
  cfg = config.services.alist;
  settingsFormat = pkgs.formats.json { };
in
{
  options.services.alist = {
    enable = mkOption {
      type = types.bool;
      default = false;
    };

    settings = lib.mkOption {
      type = lib.types.submodule {
        freeformType = settingsFormat.type;
        options = { };
      };
      default = { };
      description = ''
        check https://alist.nn.ci/config/configuration.html for documentation.
      '';
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/alist";
    };

    user = mkOption {
      type = types.str;
      default = "alist";
    };

    group = mkOption {
      type = types.str;
      default = "alist";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.alist ];

    systemd.services.alist = {
      after = [ "network.target" ];
      description = "Alist service";
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.alist ];
      preStart = ''
        umask 0077
        mkdir -p ${cfg.dataDir}/data
        ${utils.genJqSecretsReplacementSnippet cfg.settings "${cfg.dataDir}/data/config.json"}
      '';
      serviceConfig = {
        ExecStart = "${pkgs.alist}/bin/alist server";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.dataDir;
        # hardening
        ReadWritePaths = [ cfg.dataDir ];
        NoExecPaths = [ "/" ];
        ExecPaths = [ "/nix/store" ];
        LockPersonality = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateMounts = true;
        PrivateTmp = true;
        PrivateUsers = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "strict";
        RemoveIPC = true;
        RestrictNamespaces = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = "@system-service";
      };
    };

    users.users = mkIf (cfg.user == "alist") {
      alist = {
        group = cfg.group;
        home = cfg.dataDir;
        createHome = true;
        isSystemUser = true;
        description = "alist user";
      };
    };

    users.groups =
      mkIf (cfg.group == "alist") { alist = { gid = null; }; };
  };
}
