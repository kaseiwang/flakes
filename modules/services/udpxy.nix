{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.udpxy;
in
{
  options.services.udpxy = {
    enable = mkOption {
      type = types.bool;
      default = false;
    };

    mcastaddr = mkOption {
      type = types.str;
      default = "0.0.0.0";
    };

    binaddr = mkOption {
      type = types.str;
      default = "0.0.0.0";
    };

    user = mkOption {
      type = types.str;
      default = "udpxy";
    };

    group = mkOption {
      type = types.str;
      default = "udpxy";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.udpxy ];
    systemd.services.udpxy = {
      after = [ "network.target" ];
      description = "udpxy Daemon";
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.udpxy ];
      serviceConfig = {
        ExecStart = ''
          ${pkgs.udpxy}/bin/udpxy -T -S -m ${cfg.mcastaddr} -a ${cfg.binaddr} -p 4022 -B 1Mb -M 55
        '';
        # To prevent "Quit & shutdown daemon" from working; we want systemd to
        # manage it!
        Restart = "on-success";
        User = cfg.user;
        Group = cfg.group;
        UMask = "0002";
      };
    };

    users.users = mkIf (cfg.user == "udpxy") {
      udpxy = {
        group = cfg.group;
        createHome = false;
        isSystemUser = true;
      };
    };

    users.groups = mkIf (cfg.group == "udpxy") {
      udpxy = {
        gid = null;
      };
    };
  };
}
