{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.sozu;
  format = pkgs.formats.toml { };
  configFile = format.generate "sozu.toml" cfg.settings;
  openFilesLimit = 65536;
in
{
  options.services.sozu = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Run sozu headlessly as systemwide daemon
      '';
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/sozu";
      description = ''
        The directory where sozu will create files.
      '';
    };

    stateDir = mkOption {
      type = types.path;
      default = "/run/sozu";
    };

    user = mkOption {
      type = types.str;
      default = "sozu";
      description = ''
        User account under which sozu runs.
      '';
    };

    group = mkOption {
      type = types.str;
      default = "sozu";
      description = ''
        Group under which sozu runs.
      '';
    };

    openFilesLimit = mkOption {
      default = openFilesLimit;
      description = ''
        Number of files to allow sozu to open.
      '';
    };

    settings = mkOption {
      type = types.attrsOf format.type;
      description = mdDoc ''
        Settings on what to generate. Please read the
        [upstream documentation](https://github.com/sozu-proxy/sozu/blob/main/doc/configure.md)
        for further information.
      '';
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.sozu ];

    systemd.services.sozu = {
      after = [ "network.target" ];
      description = "Sozu - A HTTP reverse proxy, configurable at runtime, fast and safe, built in Rust.";
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.sozu ];
      serviceConfig = {
        PIDFile = "${cfg.stateDir}/sozu.pid";
        ExecStartPre = ''
          ${pkgs.sozu}/bin/sozu config check --config ${configFile}
        '';
        ExecStart = ''
          ${pkgs.sozu}/bin/sozu start --config ${configFile}
        '';
        ExecReload = ''
          ${pkgs.sozu}/bin/sozu reload --config ${configFile}
        '';
        Restart = "on-failure";
        User = cfg.user;
        Group = cfg.group;
        UMask = "0002";
        LimitNOFILE = cfg.openFilesLimit;
      };
    };

    users.users = mkIf (cfg.user == "sozu") {
      sozu = {
        group = cfg.group;
        home = cfg.dataDir;
        createHome = true;
        isSystemUser = true;
        description = "sozu user";
      };
    };

    users.groups = mkIf (cfg.group == "sozu") {
      sozu = {
        gid = null;
      };
    };
  };
}
