{ config, lib, ... }:
let
  cfg = config.environment.nas0Cache;
in
{
  options.environment.nas0Cache = {
    enable = lib.mkEnableOption "nas0's Harmonia binary cache as a LAN substituter";
  };

  config = lib.mkIf cfg.enable {
    nix.settings = {
      # Priority comes from the server's nix-cache-info (30).
      extra-substituters = [ "https://cache-nas0.i.kasei.im" ];
      extra-trusted-public-keys = [ "nas0.i.kasei.im-1:t/JD5pr1rfiup+SxpSEVRLRt+2mceZ9XJZyTqoJvNAQ=" ];
      # Fail fast when nas0 is unreachable instead of stalling every Nix command.
      # Global: it also bounds connects to every other substituter and fetch.
      connect-timeout = lib.mkDefault 5;
    };
  };
}
