{ config, pkgs, inputs, ... }:
{
  environment.baseline.enable = true;

  time.timeZone = "Asia/Shanghai";

  i18n = {
    defaultLocale = "zh_CN.UTF-8";
    extraLocaleSettings = {
      LC_ALL = "zh_CN.UTF-8";
      LANGUAGE = "zh_CN.UTF8";
    };
  };

  fonts = {
    enableDefaultPackages = false;
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      noto-fonts-emoji
      wqy_microhei
      jetbrains-mono
      (nerdfonts.override { fonts = [ "JetBrainsMono" "Noto" ]; })
    ];
    fontDir.enable = true;
    fontconfig = {
      defaultFonts = pkgs.lib.mkForce {
        serif = [ "Noto Serif CJK SC" "Noto Serif" ];
        sansSerif = [ "Noto Sans CJK SC" "Noto Sans" ];
        monospace = [ "Noto Sans Mono" "Noto Sans Mono CJK SC" ];
        emoji = [ "Noto Color Emoji" ];
      };
      subpixel = {
        rgba = "rgb";
        lcdfilter = "default";
      };
    };
  };

  sops = {
    age = {
      keyFile = "/var/lib/sops.key";
      sshKeyPaths = [ ];
    };
    gnupg.sshKeyPaths = [ ];
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      wgcf-key = { };
      u2f-keys = { mode = "0444"; };
      btrbk-sshkey = {
        mode = "0400";
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
      substituters = pkgs.lib.mkForce [
        #"https://mirrors.bfsu.edu.cn/nix-channels/store" # 302 tuna
        #"https://mirrors.nju.edu.cn/nix-channels/store"
        #"https://mirror.nyist.edu.cn/nix-channels/store"
        #"https://mirrors.cqupt.edu.cn/nix-channels/store"
        #"https://mirrors.ustc.edu.cn/nix-channels/store"
        #"https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
        #"https://mirrors.sjtug.sjtu.edu.cn/nix-channels/store"
        "https://cache.nixos.org"
      ];
    };
  };

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (pkgs.lib.getName pkg) [
    "feishu"
    "vscode"
    "vscode-extension-ms-vscode-remote-remote-ssh"
    "vscode-extension-github-copilot"
    "vscode-extension-github-copilot-chat"
    "vscode-extension-signageos-signageos-vscode-sops" # https://github.com/signageos/vscode-sops/pull/75
  ];

  programs = {
    dconf.enable = true;
    adb.enable = true;
    wireshark.enable = true;
    #virt-manager.enable = true;
    fuse.userAllowOther = true;
    hyprland.enable = true;
    #ryzen-monitor-ng.enable = true;
  };

  services.dbus.implementation = "broker";

  users.users.kasei = {
    extraGroups = [ "docker" "fuse" "adbusers" "wireshark" ];
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    sharedModules = [
      inputs.sops-nix.homeManagerModules.sops
      inputs.nix-index-database.hmModules.nix-index
      #inputs.hyprland.homeManagerModules.default
    ];
    users.kasei = {
      imports = [
        ./dconf.nix
        ./home.nix
      ];
    };
  };

  virtualisation = {
    docker = {
      enable = true;
      storageDriver = "btrfs";
    };
  };

  security = {
    polkit.enable = true;
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

    krb5 = {
      enable = true;
      settings = {
        libdefaults = {
          default_realm = "CORP.NETEASE.COM";
        };
        domain_realm = {
          "netease.com" = "CORP.NETEASE.COM";
        };
        realms = {
          "CORP.NETEASE.COM" = {
            default_domain = "netease.com";
            admin_server = "kdc-internal.corp.netease.com";
            kdc = [
              "kdc-internal.corp.netease.com"
              "kdc-hzinternal1.corp.netease.com"
              "kdc-internet.corp.netease.com"
            ];
          };
        };
      };
    };
  };

  xdg.portal = {
    enable = true;
  };

  environment = {
    systemPackages = with pkgs; [
      amdgpu_top
      config.boot.kernelPackages.cpupower
      man-pages
      man-pages-posix
      # gnome
      gnome-tweaks
      dconf-editor
      gnome-screenshot
      eog
      gnomeExtensions.kimpanel
      gnomeExtensions.caffeine
      gnomeExtensions.system-monitor-next
      xorg.xhost
    ];
    gnome.excludePackages = (with pkgs; [
      epiphany # web browser
      totem # video player
      gnome.tali # poker game
      gnome.iagno # go game
      gnome.hitori # sudoku game
      gnome.atomix # puzzle game
    ]);
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
