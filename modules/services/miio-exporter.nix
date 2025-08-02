{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.miio-exporter;
  scriptBin = pkgs.python3.withPackages (
    ps: with ps; [
      python-miio
      prometheus-client
    ]
  );
  scriptText = pkgs.writeText "miio-prometheus-exporter.py" ''
    #!/usr/bin/env python3

    import time
    import os
    from miio import AirPurifier
    from prometheus_client import start_http_server, Gauge

    HOST = os.environ['HOST']
    TOKEN = os.environ['TOKEN']

    ap = AirPurifier(HOST, TOKEN)

    AQI = Gauge('miio_air_quality_index', 'Air Quality Index')
    HUMIDITY = Gauge('miio_air_humidity', 'humidity')
    TEMPERATURE = Gauge('miio_air_temperature','temperature')
    MOTERSPEED= Gauge('miio_motor_speed', 'motor speed')

    def update_status():
        status = ap.status()
        AQI.set(status.aqi)
        HUMIDITY.set(status.humidity)
        TEMPERATURE.set(status.temperature)
        MOTERSPEED.set(status.motor_speed)

    if __name__ == '__main__':
        start_http_server(9191)
        while True:
            time.sleep(15)
            update_status()
  '';
in
{
  options.services.miio-exporter = {
    enable = mkOption {
      type = types.bool;
      default = false;
    };
    environmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
    };
  };

  config = mkIf cfg.enable {
    systemd.services."miio-exporter" = {
      description = "XiaoMi IoT Prometheus Exporter";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        DynamicUser = true;
        StandardOutput = "journal";
        ExecStart = ''
          ${scriptBin}/bin/python ${scriptText}
        '';
        Restart = "always";
      }
      // optionalAttrs (cfg.environmentFile != null) {
        EnvironmentFile = cfg.environmentFile;
      };
    };
  };
}
