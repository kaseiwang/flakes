{
  config,
  pkgs,
  ...
}:
let
  sambaOptions = [
    "credentials=${config.sops.secrets.nas0-smb-credentials.path}"
    "uid=kasei"
    "gid=users"
    "nofail"
    "x-systemd.automount"
    "x-systemd.mount-timeout=15s"
  ];
in
{
  sops.defaultSopsFile = ./secrets.yaml;
  sops.secrets = {
    tinced25519 = { };
    singboxpass = { };
    # CIFS credentials file: username=... and password=... on separate lines.
    nas0-smb-credentials = {
      owner = "root";
      mode = "0400";
    };
  };

  boot.supportedFilesystems = [ "cifs" ];

  fileSystems = {
    "/home/kasei/samba/nas0" = {
      device = "//nas0.i.kasei.im/nas0";
      fsType = "cifs";
      options = sambaOptions;
    };
    "/home/kasei/samba/qbittorrent" = {
      device = "//nas0.i.kasei.im/qbittorrent";
      fsType = "cifs";
      options = sambaOptions ++ [ "ro" ];
    };
  };

  services = {
    feilian = {
      enable = true;
      autoStart = false;
      companyId = "bytedance";
    };

    xserver = {
      enable = true;
      videoDrivers = [ "nvidia" ];
    };
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
