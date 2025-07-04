{ config, pkgs, inputs, ... }:
{
  environment.baseline.enable = true;

  environment.myhome = {
    enable = true;
    gui = true;
  };

  fonts = {
    fontconfig = {
      subpixel = {
        rgba = "rgb";
        lcdfilter = "default";
      };
    };
  };

  sops = {
    age = {
      keyFile = "/var/lib/sops.key";
    };
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      u2f-keys = { mode = "0444"; };
      btrbk-sshkey = {
        owner = config.users.users."btrbk".name;
      };
      networkmanager-env = { };
    };
  };

  systemd.coredump = {
    enable = true;
    extraConfig = ''
      Storage=none
    '';
  };

  nix = {
    settings = {
      system-features = [
        "kvm"
        "uid-range"
        "big-parallel"
      ];
      substituters = [
        "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
        "https://mirrors.ustc.edu.cn/nix-channels/store"
        "https://cache.nixos.org/"
      ];
    };
  };

  programs = {
    dconf.enable = true;
    adb.enable = true;
    wireshark.enable = true;
    fuse.userAllowOther = true;
  };

  services.dbus.implementation = "broker";

  users.users.kasei = {
    extraGroups = [ "docker" "fuse" "adbusers" "wireshark" ];
  };

  virtualisation = {
    docker = {
      enable = true;
      storageDriver = "btrfs";
    };
  };

  security = {
    pam.u2f = {
      enable = true;
      control = "sufficient";
      settings = {
        cue = true;
        origin = "pam://u2f.kasei.im";
        appId = "pam://u2f.kasei.im";
        authFile = config.sops.secrets.u2f-keys.path;
      };
    };
  };

  environment = {
    systemPackages = with pkgs; [
      amdgpu_top
      config.boot.kernelPackages.cpupower
      man-pages
      man-pages-posix
    ];
    etc = {
      "nfc/libnfc.conf" = {
        mode = "0555";
        text = ''
          # Allow device auto-detection (default: true)
          # Note: if this auto-detection is disabled, user has to set manually a device
          # configuration using file or environment variable
          allow_autoscan = true

          # Allow intrusive auto-detection (default: false)
          # Warning: intrusive auto-detection can seriously disturb other devices
          # This option is not recommended, user should prefer to add manually his device.
          allow_intrusive_scan = false

          # Set log level (default: error)
          # Valid log levels are (in order of verbosity): 0 (none), 1 (error), 2 (info), 3 (debug)
          # Note: if you compiled with --enable-debug option, the default log level is "debug"
          log_level = 3
          device.name = "pn532"
          device.connstring = "pn532_uart:/dev/ttyUSB0"
        '';
      };
      "nfc/devices.d/pn532_via_uart2usb.conf " = {
        mode = "0555";
        text = ''
          name = "Adafruit PN532 board via UART"
          connstring = pn532_uart:/dev/ttyUSB0
          allow_intrusive_scan = true
          log_level = 3
        '';
      };
    };
  };

  environment.persistence."/persist" = {
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
    ];
    directories = [
      "/var/lib"
    ];
  };

  documentation = {
    nixos.enable = pkgs.lib.mkForce true;
    man = {
      enable = true;
    };
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "22.05"; # Did you read the comment?
}
