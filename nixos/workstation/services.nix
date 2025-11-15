{ config, pkgs, ... }:
{
  sops.defaultSopsFile = ./secrets.yaml;
  sops.secrets = {
    tinced25519 = { };
    singboxpass = { };
  };

  services = {
    xserver.enable = true;
    displayManager.gdm.enable = true;
    desktopManager.gnome.enable = true;

    pipewire = {
      enable = true;
      pulse.enable = true;
    };

    gnome = {
      evolution-data-server.enable = true;
      gnome-keyring.enable = true;
    };

    pcscd.enable = true;
    fwupd.enable = true;

    udev.packages = with pkgs; [
      yubikey-personalization
    ];

    openssh.settings.PasswordAuthentication = pkgs.lib.mkForce true;

    btrbk = {
      ioSchedulingClass = "idle";
      instances = {
        "${config.networking.hostName}" = {
          onCalendar = "hourly";
          settings = {
            snapshot_preserve = "72h";
            snapshot_preserve_min = "3h";
            target_preserve = "144h 14d 14w";
            target_preserve_min = "no";
            snapshot_dir = "_btrbk_snapshots";
            ssh_identity = "${config.sops.secrets.btrbk-sshkey.path}";
            stream_compress = "zstd";
            stream_compress_level = "1";
            stream_buffer = "128m";
            volume = {
              "/mnt/bareroot" = {
                subvolume = {
                  "nixos_persist" = { };
                  "homevol_kasei" = { };
                };
                target = "ssh://nas0.i.kasei.im/mnt/backup_disk/${config.networking.hostName}";
              };
            };
          };
        };
      };
    };
  };
}
