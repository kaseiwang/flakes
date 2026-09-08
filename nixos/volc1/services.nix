{ config, pkgs, ... }:
{
  services = {
    prometheus = {
      exporters = {
        node = {
          enable = true;
          enabledCollectors = [
            "systemd"
            "ethtool"
            "interrupts"
          ];
        };
      };
    };
  };
}
