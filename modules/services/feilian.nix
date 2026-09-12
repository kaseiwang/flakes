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
    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to start the FeiLian service automatically at boot.";
    };
    package = lib.mkPackageOption pkgs "feilian" { };
    companyId = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Company ID normally supplied in braces in the Debian installer filename.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    systemd.tmpfiles.rules = [ "d /etc/NetworkManager/dnsmasq.d 0755 root root -" ];
    systemd.services.feilian = {
      description = "FeiLian Service";
      aliases = [ "corplink.service" ];
      after = [ "network.target" ];
      wantedBy = lib.optional cfg.autoStart "multi-user.target";
      preStart = ''
        # FeiLian writes RPC credentials, device identity and logs beside its executable.
        # Copy the payload out of the store, retaining generated state on upgrades.
        payload=${cfg.package.unpacked}/opt/apps/com.volcengine.feilian/files
        if [ "$(cat "$STATE_DIRECTORY/.nix-package" 2>/dev/null || true)" != "$payload" ]; then
          ${pkgs.rsync}/bin/rsync -rltp --chmod=u+w "$payload/" "$STATE_DIRECTORY/"
          printf '%s\n' "$payload" > "$STATE_DIRECTORY/.nix-package"
        fi
      ''
      + lib.optionalString (cfg.companyId != null) ''
        install -m 0644 ${
          pkgs.writeText "feilian-company.json" (builtins.toJSON { company_id = cfg.companyId; })
        } "$STATE_DIRECTORY/corplink.conf"
      '';
      serviceConfig = {
        StateDirectory = "feilian";
        StateDirectoryMode = "0755";
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
