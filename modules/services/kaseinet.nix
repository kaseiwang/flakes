{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.kaseinet;
  interfaceName = "kaseinet";
  routeMetric = 1024;
  metricOptionName = if config.networking.useNetworkd then "Metric" else "metric";
in
{
  options.services.kaseinet = {
    enable = mkOption {
      type = types.bool;
      default = false;
    };
    name = mkOption {
      type = types.nullOr types.str;
      default = null;
    };
    v4addr = mkOption {
      type = types.str;
      default = "";
    };
    v6addr = mkOption {
      type = types.str;
      default = "";
    };
    ed25519PrivateKeyFile = mkOption {
      type = types.path;
      default = "";
    };
    extraConfig = mkOption {
      type = types.lines;
      default = "";
    };
  };

  config = mkIf cfg.enable {
    services.tinc.networks."${interfaceName}" = {
      package = pkgs.tinc_pre;
      name = cfg.name;
      ed25519PrivateKeyFile = cfg.ed25519PrivateKeyFile;
      extraConfig = cfg.extraConfig;
      hostSettings = {
        n3160 = {
          addresses = [
            { address = "cmcc.i.kasei.im"; }
          ];
          subnets = [
            { address = "10.10.0.6/32"; }
            { address = "fdcd:ad38:cdc5:3::6/128"; }
            { address = "10.10.2.0/24"; }
            { address = "fdcd:ad38:cdc5:1::/64"; }
          ];
          settings = {
            Ed25519PublicKey = "S3MDWMD+hTprR5ibFJK/awF9yX3/Ige71cPmXdLKwuD";
            FWMark = "200";
          };
        };
        nanopir5c = {
          addresses = [
            { address = "ne.kasei.im"; }
          ];
          subnets = [
            { address = "10.10.0.111/32"; }
            { address = "fdcd:ad38:cdc5:3::111/128"; }
            { address = "10.10.3.0/24"; }
            { address = "fdcd:ad38:cdc5:2::/64"; }
          ];
          settings = {
            Ed25519PublicKey = "kNTDbC2aZGZ+Xa/TAwudlXVKQ9DH7kRMcC/IZY+ZOmE";
            FWMark = "200";
            DirectOnly = "yes";
          };
        };
        c940 = {
          subnets = [
            { address = "10.10.0.110/32"; }
            { address = "fdcd:ad38:cdc5:3::110/128"; }
          ];
          settings = {
            Ed25519PublicKey = "+vVoAJBfZuAcDfXedYBeNvi+aYYnSgK9N78gEqIv6dE";
          };
        };
        gz1 = {
          addresses = [
            { address = "81.71.146.69"; }
          ];
          subnets = [
            { address = "10.10.0.11/32"; }
            { address = "fdcd:ad38:cdc5:3::11/128"; }
          ];
          settings = {
            Ed25519PublicKey = "0+jHnNHuN3W6M7k4n8A17QhrnzKeTcAnhO/1kJZQSWD";
          };
        };
      };
    };

    networking.interfaces."tinc.kaseinet" = {
      mtu = 1400;
      useDHCP = false;

      ipv4.addresses = [
        {
          address = cfg.v4addr;
          prefixLength = 32;
        }
      ];
      ipv6.addresses = [
        {
          address = cfg.v6addr;
          prefixLength = 128;
        }
      ];

      ipv4.routes = [
        {
          address = "10.10.0.0";
          prefixLength = 24;
          options = {
            ${metricOptionName} = "${toString routeMetric}";
          };
        }
        {
          address = "10.10.2.0";
          prefixLength = 24;
          options = {
            ${metricOptionName} = "${toString routeMetric}";
          };
        }
        {
          address = "10.10.3.0";
          prefixLength = 24;
          options = {
            ${metricOptionName} = "${toString routeMetric}";
          };
        }
      ];
      ipv6.routes = [
        {
          address = "fdcd:ad38:cdc5:1::";
          prefixLength = 64;
          options = {
            ${metricOptionName} = "${toString routeMetric}";
          };
        }
        {
          address = "fdcd:ad38:cdc5:2::";
          prefixLength = 64;
          options = {
            ${metricOptionName} = "${toString routeMetric}";
          };
        }
        {
          address = "fdcd:ad38:cdc5:3::";
          prefixLength = 64;
          options = {
            ${metricOptionName} = "${toString routeMetric}";
          };
        }
      ];
    };
  };
}
