{ config, lib, pkgs, ... }: with lib;
let
  cfg = config.services.vlmcsd;
in
{
  options.services.vlmcsd = {
    enable = mkOption {
      type = types.bool;
      default = false;
    };

    port = mkOption {
      type = types.port;
      default = 1688;
    };
  };

  config = mkIf cfg.enable {

    environment.systemPackages = [ pkgs.vlmcsd ];

    systemd.sockets.vlmcsd = {
      description = "KMS Emulator Listening Socket";
      wantedBy = [ "sockets.target" ];
      listenStreams = [ "${toString cfg.port}" ];
      socketConfig.Accept = "yes";
    };

    systemd.services."vlmcsd@" = {
      description = "KMS Emulator Service";
      requires = [ "vlmcsd.socket" ];
      serviceConfig = {
        DynamicUser = true;
        StandardInput = "socket";
        StandardOutput = "journal";
        ExecStart = ''
          ${pkgs.vlmcsd}/bin/vlmcsd -e -D
        '';
      };
    };
  };
}
