{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.feilian;
in
{
  options.services.feilian = {
    enable = lib.mkEnableOption "FeiLian client and service";
    package = lib.mkPackageOption pkgs "feilian" { };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    systemd.tmpfiles.rules = [ "d /etc/NetworkManager/dnsmasq.d 0755 root root -" ];
    systemd.services.feilian = {
      description = "FeiLian Service";
      aliases = [ "corplink.service" ];
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/feilian-service";
        Restart = "on-failure";
        RestartSec = "3s";
        User = "root";
        Group = "root";
        CapabilityBoundingSet = [
          "CAP_NET_ADMIN"
          "CAP_NET_BIND_SERVICE"
          "CAP_NET_RAW"
          "CAP_SYS_ADMIN"
        ];
        AmbientCapabilities = [
          "CAP_NET_ADMIN"
          "CAP_NET_BIND_SERVICE"
          "CAP_NET_RAW"
          "CAP_SYS_ADMIN"
        ];
      };
    };
  };
}
