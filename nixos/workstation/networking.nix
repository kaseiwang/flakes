{ config, ... }:

{
  networking = {
    hostName = "workstation";
    useDHCP = false;
    useNetworkd = true;
    firewall.enable = false;

    proxy.default = "http://10.10.5.1:1080";

    networkmanager.enable = false;
    wireless.iwd = {
      enable = true;
      settings.General.EnableNetworkConfiguration = false;
    };
  };

  services.resolved.enable = true;

  systemd.network = {
    enable = true;
    # Either wired or wireless connectivity is sufficient for this desktop.
    wait-online.enable = false;
    networks = {
      "20-wired" = {
        matchConfig = {
          Type = "ether";
          # Only physical devices; leave Docker, tinc and VPN links alone.
          Path = "*";
        };
        networkConfig = {
          DHCP = "yes";
          IPv6AcceptRA = true;
        };
        dhcpV4Config.RouteMetric = 100;
        ipv6AcceptRAConfig.RouteMetric = 100;
      };
      "30-wifi" = {
        matchConfig.Type = "wlan";
        networkConfig = {
          DHCP = "yes";
          IPv6AcceptRA = true;
        };
        dhcpV4Config.RouteMetric = 600;
        ipv6AcceptRAConfig.RouteMetric = 600;
      };
    };
  };

  # Seed writable iwd profiles from SOPS; C preserves existing local profiles.
  systemd.tmpfiles.settings."10-iwd" = {
    "/var/lib/iwd".d.mode = "0700";
    "/var/lib/iwd/kaseinet.psk".C = {
      mode = "0600";
      argument = config.sops.secrets."wireless/kaseinet".path;
    };
  };
}
