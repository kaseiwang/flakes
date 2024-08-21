{ pkgs, lib, config, ... }:
{
  programs.neovim = {
    enable = true;
    vimAlias = true;
    vimdiffAlias = true;
  };

  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      tide configure --auto --style=Lean --prompt_colors='True color' --show_time='24-hour format' --lean_prompt_height='One line' --prompt_spacing=Compact --icons='Many icons' --transient=No
      tide reload
    '';
    plugins = [
      { name = "tide"; src = pkgs.fishPlugins.tide.src; }
      { name = "fzf.fish"; src = pkgs.fishPlugins.fzf-fish.src; }
    ];
  };

  programs.tmux = {
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

  # workaround https://github.com/NixOS/nixpkgs/issues/196651
  manual.manpages.enable = false;

  home.stateVersion = "22.05";
}
