{ lib, osConfig, ... }:
lib.mkIf osConfig.programs.hyprland.enable (
  lib.mkMerge [
    (import ./waybar.nix { inherit lib; })
    {
      wayland.windowManager = {
        hyprland = {
          enable = true;
          # UWSM owns the session; HM's stop hook would stop graphical-session.target.
          systemd.enable = !osConfig.programs.hyprland.withUWSM;
          configType = "lua";
          extraLuaFiles.config = ./hyprland.lua;
        };
      };

      programs = {
        hyprshot.enable = true;
        hyprlock = {
          enable = true;
          settings.input-field = [
            {
              monitor = "";
              size = "300, 50";
              position = "0, 0";
              halign = "center";
              valign = "center";
              fade_on_empty = false;
            }
          ];
        };
      };

      services = {
        hyprlauncher = {
          enable = true;
        };
      };
    }
  ]
)
