{ pkgs, lib, config, ... }:
let
  mkWrap = name: cmd: pkgs.writeShellScriptBin name "exec ${cmd} \"$@\"";
  tide = pkgs.fetchFromGitHub {
    owner = "IlanCosman";
    repo = "tide";
    rev = "v5.4.0";
    sha256 = "sha256-jswV+M3cNC3QnJxvugk8VRd3cOFmhg5ejLpdo36Lw1g=";
  };
in
{
  gtk = {
    enable = true;
    theme = {
      package = pkgs.materia-theme;
      name = "Materia";
    };
    iconTheme = {
      package = pkgs.numix-icon-theme-circle;
      name = "Numix-Circle";
    };
    font = {
      package = pkgs.roboto;
      name = "Roboto";
      size = 11;
    };
    gtk2.configLocation = "${config.xdg.configHome}/gtk-2.0/gtkrc";
  };
  qt = {
    enable = true;
    platformTheme = "gtk";
  };

  programs.neovim = {
    enable = true;
    vimAlias = true;
    vimdiffAlias = true;
    plugins = with pkgs.vimPlugins; [
      nvim-lspconfig
      nvim-cmp
      cmp-nvim-lsp
      everforest
      luasnip
      vim-lastplace
      editorconfig-nvim
      lualine-nvim
      which-key-nvim
      lualine-lsp-progress
      (nvim-treesitter.withPlugins (
        plugins: with plugins; [
          tree-sitter-nix
          tree-sitter-lua
          tree-sitter-rust
          tree-sitter-go
        ]
      ))
    ];
    extraConfig = ''
      set viminfo+=n${config.xdg.stateHome}/viminfo
      let g:everforest_background = 'soft'
      colorscheme everforest
      lua << EOT
      ${builtins.readFile ./nvim.lua}
      EOT
    '';
  };
  programs.firefox = {
    enable = true;
    package = pkgs.wrapFirefox pkgs.firefox-unwrapped {
      forceWayland = true;
      extraPolicies = {
        PasswordManagerEnabled = false;
        DisableFirefoxAccounts = true;
        DisablePocket = true;
        EnableTrackingProtection = {
          Value = true;
          Locked = true;
          Cryptomining = true;
          Fingerprinting = true;
        };
        Proxy = {
          Mode = "manual";
          SOCKSProxy = "127.0.0.1:1080";
          SOCKSVersion = 5;
          UseProxyForDNS = true;
        };
        Preferences = {
          "browser.newtabpage.activity-stream.feeds.topsites" = false;
          "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
        };
        ExtensionSettings = {
          "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
            installation_mode = "force_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi";
          };
        };
      };
    };
    profiles = {
      default = {
        settings = {
          "fission.autostart" = true;
          "browser.urlbar.autoFill.adaptiveHistory.enabled" = true;
          "media.peerconnection.enabled" = false;
        };
      };
    };
  };
  home.packages = with pkgs; [
    alacritty
    foot
    mpv
    tdesktop
    waypipe
    xdg-utils
    pavucontrol
    brightnessctl
    ripgrep
    ncdu
    wireguard-tools
    nixpkgs-fmt
    rnix-lsp
    ccls
    vscodium
    smartmontools
    python3
    knot-dns
    tree
    mtr
    sops
    restic
    libarchive
    (mkWrap "terraform" "${coreutils}/bin/env CHECKPOINT_DISABLE=1 ${
      terraform.withPlugins (ps: with ps; [ vultr sops gandi ])
        }/bin/terraform")
  ];

  home.sessionVariables = {
    EDITOR = "nvim";
    #SSH_AUTH_SOCK = "$XDG_RUNTIME_DIR/resign.ssh";
    #SOPS_GPG_EXEC = "resign-gpg";
    # cache
    __GL_SHADER_DISK_CACHE_PATH = "${config.xdg.cacheHome}/nv";
    CUDA_CACHE_PATH = "${config.xdg.cacheHome}/nv";
    CARGO_HOME = "${config.xdg.cacheHome}/cargo";
    # state
    HISTFILE = "${config.xdg.stateHome}/bash_history";
    LESSHISTFILE = "${config.xdg.stateHome}/lesshst";
    #GNUPGHOME = pkgs.writeTextDir "pubring.gpg" (builtins.readFile ./pubring.gpg);
    # shit
    PYTHONSTARTUP = (
      pkgs.writeText "start.py" ''
        import readline
        readline.write_history_file = lambda *args: None
      ''
    ).outPath;
  };

  systemd.user = {
    targets.sway-session.Unit.Wants = [ "xdg-desktop-autostart.target" ];
  };

  programs = {
    direnv = {
      enable = true;
      nix-direnv = {
        enable = true;
      };
    };
    git = {
      enable = true;
      userEmail = "nickcao@nichi.co";
      userName = "Nick Cao";
      extraConfig = {
        commit.gpgSign = true;
        gpg = {
          format = "ssh";
          ssh.defaultKeyCommand = "ssh-add -L";
          ssh.allowedSignersFile = toString (pkgs.writeText "allowed_signers" ''
          '');
        };
        merge.conflictStyle = "diff3";
        merge.tool = "vimdiff";
        mergetool = {
          keepBackup = false;
          keepTemporaries = false;
          writeToTemp = true;
        };
        pull.rebase = true;
        init.defaultBranch = "master";
        fetch.prune = true;
      };
    };
    fish = {
      enable = true;
      plugins = [{
        name = "tide";
        src = tide;
      }];
      shellInit = ''
        set fish_greeting

        function fish_user_key_bindings
          fish_vi_key_bindings
          bind f accept-autosuggestion
        end

        string replace -r '^' 'set -g ' < ${tide}/functions/tide/configure/configs/lean.fish         | source
        string replace -r '^' 'set -g ' < ${tide}/functions/tide/configure/configs/lean_16color.fish | source
        set -g tide_prompt_add_newline_before false

        set fish_color_normal normal
        set fish_color_command blue
        set fish_color_quote yellow
        set fish_color_redirection cyan --bold
        set fish_color_end green
        set fish_color_error brred
        set fish_color_param cyan
        set fish_color_comment red
        set fish_color_match --background=brblue
        set fish_color_selection white --bold --background=brblack
        set fish_color_search_match bryellow --background=brblack
        set fish_color_history_current --bold
        set fish_color_operator brcyan
        set fish_color_escape brcyan
        set fish_color_cwd green
        set fish_color_cwd_root red
        set fish_color_valid_path --underline
        set fish_color_autosuggestion white
        set fish_color_user brgreen
        set fish_color_host normal
        set fish_color_cancel --reverse
        set fish_pager_color_prefix normal --bold --underline
        set fish_pager_color_progress brwhite --background=cyan
        set fish_pager_color_completion normal
        set fish_pager_color_description B3A06D --italics
        set fish_pager_color_selected_background --reverse
      '';
      shellAliases = {
        b = "brightnessctl";
        freq = "sudo ${pkgs.linuxPackages.cpupower}/bin/cpupower frequency-set -g";
      };
      shellAbbrs = {
        rebuild = "nixos-rebuild --use-remote-sudo -v -L --flake /home/nickcao/Projects/flakes";
      };
    };
    tmux = {
      enable = true;
      baseIndex = 1;
      escapeTime = 10;
      shell = "${pkgs.fish}/bin/fish";
      keyMode = "vi";
      terminal = "screen-256color";
      extraConfig = ''
        set -g status-position top
        set -g set-clipboard on
        set -g mouse on
        set -g status-right ""
        set -g renumber-windows on
        new-session -s main
      '';
    };
    foot = {
      enable = true;
      settings = {
        main = {
          shell = "${pkgs.tmux}/bin/tmux new-session -t main";
          font = "JetBrains Mono:size=10";
        };
        cursor = {
          color = "323d43 7fbbb3";
        };
        colors = {
          background = "323d43";
          foreground = "d8cacc";
          regular0 = "4a555b";
          regular1 = "e68183";
          regular2 = "a7c080";
          regular3 = "dbbc7f";
          regular4 = "7fbbb3";
          regular5 = "d699b6";
          regular6 = "83c092";
          regular7 = "d8caac";
          bright0 = "525c62";
          bright1 = "e68183";
          bright2 = "a7c080";
          bright3 = "dbbc7f";
          bright4 = "7fbbb3";
          bright5 = "d699b6";
          bright6 = "83c092";
          bright7 = "d8caac";
          selection-foreground = "3c474d";
          selection-background = "525c62";
        };
      };
    };
    ssh = {
      enable = true;
      serverAliveInterval = 42;
      extraConfig = ''
        CheckHostIP no
      '';
    };
  };

  xdg = {
    enable = true;
    userDirs = {
      enable = true;
      desktop = "$HOME";
      templates = "$HOME";
      music = "$HOME";
      videos = "$HOME";
      publicShare = "$HOME";
    };
    configFile = {
      "sioyek/prefs_user.config".text = ''
      '';
      "go/env".text = ''
        GOPATH=${config.xdg.cacheHome}/go
        GOBIN=${config.xdg.stateHome}/go/bin
        GO111MODULE=on
        GOPROXY=https://goproxy.cn
        GOSUMDB=sum.golang.google.cn
      '';
    };
  };

  home.activation.installPackages = {
    data = lib.mkForce "";
    before = lib.mkForce [ ];
    after = lib.mkForce [ ];
  };

  home.stateVersion = "22.05";
}
