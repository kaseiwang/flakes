{
  config,
  lib,
  pkgs,
  ...
}:
let
  patched-openssh = pkgs.openssh.overrideAttrs (prev: {
    patches = (prev.patches or [ ]) ++ [ ./openssh-home-config-permission.patch ];
  });
in
{
  home.packages = with pkgs; [
    # fonts
    inter
    fragment-mono
    liberation_ttf
    sarasa-gothic
    nerd-fonts.symbols-only
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    noto-fonts-emoji
    wqy_microhei
    jetbrains-mono

    btop
    ccls
    #(ccls.override { llvmPackages = pkgs.llvmPackages_latest; }) # c/c++ lsp server
    cloc # count lines of code
    devenv
    easyeffects # sound effect
    eog
    evolution # email
    feishu
    fzf
    gdb
    gdu
    gnome-screenshot
    go
    gopls # golang lsp server
    joplin-desktop
    jq # json query
    mercurial
    mpv
    nil # nix lsp server
    nix-tree # nix space usage
    offlineimap
    openssl
    python3
    python3.pkgs.ipython
    remmina # RDP client
    rustup
    smartmontools
    #(spotify.override {deviceScaleFactor = 2;})
    tdesktop
    unzip
    wireshark
    xdg-open-server # xdp proxy for app in docker
    xorg.xhost
    yubikey-manager
  ];

  sops = {
    age = {
      keyFile = "${config.xdg.configHome}/sops/age/keys.txt";
    };
    defaultSopsFile = ./secrets.yaml;
    defaultSymlinkPath = "${config.xdg.configHome}/secrets";
    secrets = {
      nixtoken = { };
      corp-ssh-config = { };
      corp-git-config = { };
      gomod-git-config = { };
    };
  };

  nix = {
    settings = {
      substituters = [
        "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
        "https://mirrors.ustc.edu.cn/nix-channels/store"
        "https://cache.nixos.org/"
      ];
    };
    extraOptions = ''
      !include ${config.sops.secrets.nixtoken.path}
    '';
  };

  gtk = {
    enable = true;
    theme = {
      name = "adwaita";
    };
    iconTheme = {
      name = "adwaita";
      package = pkgs.adwaita-icon-theme;
    };
    font = {
      name = "Noto Sans";
      size = 12;
    };
  };
  qt = {
    enable = true;
    platformTheme.name = "adwaita";
    style = {
      name = "adwaita";
      package = pkgs.adwaita-qt;
    };
  };

  fonts = {
    fontconfig = {
      enable = true;
      defaultFonts = {
        serif = [
          "Noto Serif CJK SC"
          "Noto Serif"
        ];
        sansSerif = [
          "Noto Sans CJK SC"
          "Noto Sans"
        ];
        monospace = [
          "Noto Sans Mono"
          "Noto Sans Mono CJK SC"
        ];
        emoji = [ "Noto Color Emoji" ];
      };
    };
  };

  i18n = {
    inputMethod = {
      enable = true;
      type = "fcitx5";
      fcitx5.addons = with pkgs; [
        fcitx5-chinese-addons
        fcitx5-pinyin-zhwiki
        fcitx5-pinyin-custom-pinyin-dictionary
      ];
    };
  };

  home.sessionVariables = {
    # cache
    CARGO_HOME = "${config.xdg.cacheHome}/cargo";
    # enable google sync, https://chromium.googlesource.com/experimental/chromium/src/+/b08bf82b0df37d15a822b478e23ce633616ed959/google_apis/google_api_keys.cc
    GOOGLE_DEFAULT_CLIENT_ID = "77185425430.apps.googleusercontent.com";
    GOOGLE_DEFAULT_CLIENT_SECRET = "OTJgUOQcT7lO7GsGZq2G4IlT";
    LIBCLANG_PATH = "${pkgs.libclang.lib}/lib";
  };

  programs = {
    helix = {
      enable = true;
    };

    ssh = {
      enable = true;
      enableDefaultConfig = false;
      matchBlocks = {
        "*" = {
          forwardAgent = true;
          serverAliveInterval = 42;
        };
        "10.10.*.*" = {
          user = "kasei";
        };
      };
      includes = [ "${config.sops.secrets.corp-ssh-config.path}" ];
      extraConfig = ''
        # default off in openssh 8.8 <https://www.openssh.com/txt/release-8.8>
        HostKeyAlgorithms=+ssh-rsa
        PubkeyAcceptedAlgorithms +ssh-rsa
        StrictHostKeyChecking accept-new
        KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
      '';
    };

    git = {
      enable = true;
      userName = "Kasei Wang";
      userEmail = "kasei@kasei.im";
      signing = {
        key = "BF2B11D0";
        signByDefault = true;
      };
      ignores = [
        ".envrc"
        "shell.nix"
        ".direnv/"
      ];
      extraConfig = {
        merge.tool = "vimdiff";
        pull.ffonly = true;
      };

      includes = [
        {
          condition = "gitdir:~/netease/";
          path = "${config.sops.secrets.corp-git-config.path}";
        }
        {
          path = "${config.sops.secrets.gomod-git-config.path}";
        }
      ];
    };

    go = {
      enable = true;
      env = {
        GOBIN = ".local/bin.go";
        GOPATH = ".cache/go";
      };
    };

    gpg = {
      enable = true;
    };

    gnome-shell = {
      enable = true;
      extensions = with pkgs; [
        { package = gnomeExtensions.caffeine; }
        { package = gnomeExtensions.kimpanel; }
      ];
    };

    alacritty = {
      enable = true;
      settings = {
        general = {
          import = [
            "${pkgs.alacritty-theme}/everforest_dark.toml"
          ];
        };
        env = {
          TERM = "xterm-256color";
        };
        window = {
          padding = {
            x = 2;
            y = 2;
          };
          decorations = "none";
          opacity = 0.75;
          dynamic_title = true;
        };
        font = {
          normal = {
            family = "terminal";
          };
          size = 14.0;
        };
        mouse = {
          bindings = [
            {
              mouse = "Middle";
              action = "PasteSelection";
            }
          ];
        };
        cursor = {
          style = "Underline";
        };
        bell = {
          animation = "EaseOutExpo";
          duration = 0;
        };
        scrolling = {
          history = 100000;
        };
        colors = {
          primary.background = "#000000";
          primary.foreground = "#E8DEC8";
        };
      };
    };

    foot = {
      enable = true;
      server.enable = false;
      settings = {
        main = {
          term = "xterm-256color";
          font = "monospace:size=11";
          pad = "2x2";
          dpi-aware = "yes";
          initial-window-mode = "maximized";
        };
        mouse = {
          hide-when-typing = "yes";
        };
        scrollback = {
          lines = 1000000;
        };
        url = {
          launch = "xdg-open $\{url}";
        };
        colors = {
          alpha = "0.75";
          # Everforest Dark
          background = "000000";
          foreground = "E8DEC8";
          #background = "2d353b";
          #foreground = "d3c6aa";
          regular0 = "475258";
          regular1 = "e67e80";
          regular2 = "a7c080";
          regular3 = "dbbc7f";
          regular4 = "7fbbb3";
          regular5 = "d699b6";
          regular6 = "83c092";
          regular7 = "d3c6aa";
          bright0 = "475258";
          bright1 = "e67e80";
          bright2 = "a7c080";
          bright3 = "dbbc7f";
          bright4 = "7fbbb3";
          bright5 = "d699b6";
          bright6 = "83c092";
          bright7 = "d3c6aa";
        };
        csd = {
          preferred = "server";
          size = 0;
        };
      };
    };

    firefox = {
      enable = true;
      policies = {
        PasswordManagerEnabled = false;
        DisablePocket = true;
        languagePacks = [ "zh-CN" ];
        ExtensionSettings = {
          "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
            installation_mode = "force_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi";
          };
          "uBlock0@raymondhill.net" = {
            installation_mode = "force_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
          };
        };
      };
    };

    chromium = {
      enable = true;
    };

    vscode = {
      enable = true;
      # https://github.com/nix-community/home-manager/issues/322
      package = pkgs.vscode.fhsWithPackages (_: [ patched-openssh ]);

      mutableExtensionsDir = true;
      profiles.default = {
        enableUpdateCheck = false;
        enableExtensionUpdateCheck = true;
        userSettings = {
          "editor.fontFamily" = "JetBrains Mono";
          "editor.minimap.autohide" = true;
          "editor.rulers" = [
            80
            100
            120
          ];
          "editor.inlineSuggest.enabled" = true;
          "editor.renderWhitespace" = "boundary";
          "window.titleBarStyle" = "custom";
          "search.exclude" = {
            "**/.direnv" = true;
            "**/vendor" = true;
            "**/result" = true;
          };
          "ccls.cache.directory" = "${config.xdg.cacheHome}/ccls-cache";
          "github.copilot.editor.enableAutoCompletions" = true;
          "git.openRepositoryInParentFolders" = "never"; # stop annoying popup
        };

        extensions =
          with pkgs.vscode-extensions;
          [
            #vscodevim.vim
            bbenoist.nix # nix language
            yzhang.markdown-all-in-one
            bierner.markdown-mermaid # mermaid for markdown
            davidanson.vscode-markdownlint
            golang.go
            #ms-vscode.PowerShell
            rust-lang.rust-analyzer
            #ms-python.python
            #ms-vscode-remote.remote-ssh
            #ms-vscode.makefile-tools
            #ms-kubernetes-tools.vscode-kubernetes-tools
            ms-azuretools.vscode-docker
            redhat.vscode-xml
            redhat.vscode-yaml
            #eamodio.gitlens
            #donjayamanne.githistory
            waderyan.gitblame
            github.copilot
            github.copilot-chat
            zxh404.vscode-proto3
            signageos.signageos-vscode-sops
          ]
          ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
            {
              name = "ccls";
              publisher = "ccls-project";
              version = "0.1.29";
              sha256 = "RjMYBLgbi+lgPqaqN7yh8Q8zr9euvQ+YLEoQaV3RDOA=";
            }
          ];
      };

    };

    beets = {
      enable = true;
      mpdIntegration = {
        enableStats = true;
        enableUpdate = true;
      };
      settings = {
        plugins = [
          "badfiles"
          "chroma"
          "acousticbrainz"
          "duplicates"
        ];
        chroma = {
          auto = "yes";
        };
      };
    };

    ncmpcpp = {
      enable = true;
    };
  };

  services = {
    gpg-agent = {
      enable = true;
      pinentry.package = pkgs.pinentry-gnome3;
      enableSshSupport = true;
      sshKeys = [
        "38F5EA0672B9142C0553809CB86A2CBC04248D72"
      ];
    };

    mpd = {
      enable = true;
      musicDirectory = ''${config.xdg.userDirs.music}'';
      extraConfig = ''
        audio_output {
          type     "pipewire"
          name     "pipewire"
          auto_resample    "no"
          enabled  "yes"
        }
      '';
    };

    mpdris2 = {
      enable = true;
      notifications = false;
      multimediaKeys = true;
    };
  };

  xdg = {
    enable = true;
    userDirs = {
      enable = true;
    };
    configFile = {
      "fontconfig/conf.d/20-my-fonts.conf".text = ''
        <match target="pattern">
          <test name="family">
            <string>terminal</string>
          </test>
          <edit name="family" mode="prepend">
            <string>JetBrains Mono</string>
            <string>Noto Sans Mono CJK SC</string>
            <string>Symbols Nerd Font Mono</string>
          </edit>
        </match>
      '';
      "pipewire/pipewire.conf.d/20-main.conf".text = ''
        context.properties = {
          default.clock.allowed-rates = [ 44100 48000 96000 192000 256000 512000 768000 ]
        }
      '';
      "pipewire/pipewire.conf.d/30-xd05bal.conf".text = ''
        pulse.rules = [
          {
            matches = [ { node.name = "alsa_output.usb-xduoo_XD-05_BAL-00.iec958-stereo" } ]
            actions = {
              update-props = {
                audio.rate = 96000
              }
            }
          }
        ]
      '';
    };
  };
}
