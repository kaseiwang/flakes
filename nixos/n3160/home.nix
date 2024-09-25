{ pkgs, lib, config, ... }:
{
  # workaround https://github.com/NixOS/nixpkgs/issues/196651
  manual.manpages.enable = false;

  home.stateVersion = "22.05";
}
