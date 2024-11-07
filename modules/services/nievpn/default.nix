{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.nievpn;
in
{
  options.services.nievpn = {
    enable = mkOption {
      type = types.bool;
      default = false;
    };
  };

  config = mkIf cfg.enable {
    sops.secrets = {
      # why defaultSopsFile not working?
      #defaultSopsFile = ./secrets.yaml;
      nievpnconf = {
        sopsFile = ./secrets.yaml;
        restartUnits = [ "nievpn.service" ];
      };
      savpnconf = {
        sopsFile = ./secrets.yaml;
        restartUnits = [ "savpn.service" ];
      };
      nievpnpy = {
        sopsFile = ./secrets.yaml;
        restartUnits = [ "nievpn.service" ];
        mode = "0500";
      };
    };

    systemd.services.nievpn = {
      description = "nievpn";
      after = [ "network.target" ];
      path = [ pkgs.iproute2 pkgs.nettools pkgs.oath-toolkit ];
      serviceConfig = {
        Type = "notify";
        LoadCredential = "nievpn.conf:${config.sops.secrets.nievpnconf.path}";
        RuntimeDirectory = "nievpn";
        RuntimeDirectoryMode = "0700";
        WorkingDirectory = "/var/run/nievpn";
        ExecStartPre = "${pkgs.python3.withPackages (ps: with ps;[ pycryptodome pyyaml ])}/bin/python ${config.sops.secrets.nievpnpy.path}  ${config.sops.secrets.nievpnconf.path}";
        ExecStart = "@${pkgs.openvpn.override { pkcs11Support = true; pkcs11helper = pkgs.pkcs11helper; }}/sbin/openvpn openvpn --suppress-timestamps --config /var/run/nievpn/vpn.conf";
      };
    };

    systemd.services.savpn = {
      description = "savpn";
      after = [ "network.target" ];
      path = [ pkgs.iproute2 pkgs.nettools pkgs.oath-toolkit ];
      serviceConfig = {
        Type = "notify";
        LoadCredential = "savpn.conf:${config.sops.secrets.savpnconf.path}";
        RuntimeDirectory = "savpn";
        RuntimeDirectoryMode = "0700";
        WorkingDirectory = "/var/run/savpn";
        ExecStartPre = "${pkgs.python3.withPackages (ps: with ps;[ pycryptodome pyyaml ])}/bin/python ${config.sops.secrets.nievpnpy.path}  ${config.sops.secrets.savpnconf.path}";
        ExecStart = "@${pkgs.openvpn.override { pkcs11Support = true; pkcs11helper = pkgs.pkcs11helper; }}/sbin/openvpn openvpn --suppress-timestamps --config /var/run/savpn/vpn.conf";
      };
    };
  };
}
