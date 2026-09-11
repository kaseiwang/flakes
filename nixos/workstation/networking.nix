{ config, pkgs, ... }:

with pkgs.lib;
{
  systemd.network.enable = mkForce false;
  networking = {
    hostName = "workstation";
    useDHCP = false;
    useNetworkd = false;
    firewall.enable = false;

    proxy.default = "http://10.10.5.1:1080";

    networkmanager = {
      enable = true;
      logLevel = "INFO";
      unmanaged = [
        "interface-name:tinc.kaseinet"
      ];
      ensureProfiles = {
        environmentFiles = [ "${config.sops.secrets.networkmanager-env.path}" ];
        profiles = {
          "kaseinet" = {
            connection = {
              id = "kaseinet";
              type = "wifi";
            };
            wifi = {
              mode = "infrastructure";
              ssid = "kaseinet";
            };
            wifi-security = {
              key-mgmt = "sae";
              psk = "$kaseinet_PASSWORD";
            };
            ipv4 = {
              method = "auto";
            };
            ipv6 = {
              method = "auto";
            };
          };
        };
      };
    };
  };
}
