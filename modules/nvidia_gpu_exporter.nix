{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.nvidia_gpu_exporter;
in
{
  options.services.nvidia_gpu_exporter = {
    enable = mkOption {
      type = types.bool;
      default = false;
    };
    host = mkOption {
      type = types.str;
      default = "[::1]";
    };
    port = mkOption {
      type = types.int;
      default = 9835;
    };
  };


  config = mkIf cfg.enable {
    systemd.services."nvidia_gpu_exporter" = {
      description = "Nvidia GPU exporter";
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.nvidia_gpu_exporter config.boot.kernelPackages.nvidia_x11 ];
      serviceConfig = {
        DynamicUser = true;
        StandardOutput = "journal";
        ExecStart = ''
          ${pkgs.nvidia_gpu_exporter}/bin/nvidia_gpu_exporter \
            --web.listen-address="${cfg.host}:${toString cfg.port}"
        '';
      };
    };
  };
}
