{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.ddns;
  script = ./ddns.py;
in
{
  options.services.ddns = {
    enable = mkOption {
      type = types.bool;
      default = false;
    };

    configFile = mkOption {
      type = types.path;
      default = "/etc/ddns.conf";
    };

    environment = mkOption {
      type = types.attrs;
      default = { };
    };
  };

  config = mkIf cfg.enable {
    systemd.services.ddns = {
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      environment = cfg.environment;
      serviceConfig = {
        StandardOutput = "journal";
        StandardError = "journal";
        ExecStart = "${
          pkgs.python3.withPackages (
            ps: with ps; [
              pyyaml
              pyroute2
              requests
              systemd
            ]
          )
        }/bin/python ${script} -c ${cfg.configFile}";
        Restart = "always";
        RestartSec = 3;
      };
    };
  };
}
