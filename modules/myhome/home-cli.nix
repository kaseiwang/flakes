# on stateless server env
{ config, lib, pkgs, ... }:
{
  programs = {
    nix-index.enable = true;

    direnv = {
      enable = true;
      nix-direnv = {
        enable = true;
      };
    };

    atuin = {
      enable = true;
      flags = [ "--disable-up-arrow" ];
    };

    eza = {
      enable = true;
    };

    git = {
      enable = true;
      userName = "Kasei Wang";
      userEmail = "kasei@kasei.im";
    };

    neovim = {
      enable = true;
      vimAlias = true;
      vimdiffAlias = true;
      defaultEditor = true;
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
      ];
      extraConfig = ''
        :source ${./nvim.lua}
      '';
    };

    fish = {
      enable = true;
      interactiveShellInit = ''
        ${lib.optionalString (config.services.gpg-agent.enable)
          "set -xg SSH_AUTH_SOCK (gpgconf --list-dirs agent-ssh-socket)"
        }
      '';
      plugins = [
        { name = "tide"; src = pkgs.fishPlugins.tide.src; }
        { name = "fzf"; src = pkgs.fishPlugins.fzf-fish.src; }
        { name = "forgit"; src = pkgs.fishPlugins.forgit.src; }
      ];
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
  };

  # workaround https://github.com/NixOS/nixpkgs/issues/196651
  manual.manpages.enable = false;

  home.stateVersion = "22.05";
}
