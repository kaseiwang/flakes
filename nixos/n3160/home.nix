{ pkgs, lib, config, ... }:
{
  programs.neovim = {
    enable = true;
    vimAlias = true;
    vimdiffAlias = true;
  };

  programs.fish = {
    enable = true;
    plugins = [
      { name = "tide"; src = pkgs.fishPlugins.tide.src; }
      { name = "fzf.fish"; src = pkgs.fishPlugins.fzf-fish.src; }
    ];
  };

  # workaround https://github.com/NixOS/nixpkgs/issues/196651
  manual.manpages.enable = false;

  home.stateVersion = "22.05";
}
