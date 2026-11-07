{
  lib,
  osConfig,
  pkgs,
  ...
}:
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
        hyprpaper = {
          enable = true;
          systemdTarget =
            if osConfig.programs.hyprland.withUWSM then
              "wayland-session@hyprland.desktop.target"
            else
              "hyprland-session.target";
          settings = {
            splash = false;
            wallpaper = [
              {
                monitor = "";
                path = pkgs.nixos-artwork.wallpapers.simple-blue.gnomeFilePath;
                fit_mode = "cover";
              }
            ];
          };
        };
      };
    }
  ]
)
