{ config, pkgs, ... }:
let
  wanif = "ens3";
in
with pkgs.lib;
{
  sops.secrets = {
    wgkey = {
      owner = "systemd-network";
    };
  };

  networking = {
    hostName = "cone3";
    useDHCP = false;
    useNetworkd = true;
    useDHCP = true;
    tempAddresses = "disabled";

    firewall = {
      enable = true;
      trustedInterfaces = [ "wg0" ];
      allowedTCPPorts = [
        443
        8688
      ];
      allowedUDPPorts = [
        2480
      ];
    };
  };
}
