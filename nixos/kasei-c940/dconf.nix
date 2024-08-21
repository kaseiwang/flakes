# Generated via dconf2nix: https://github.com/gvolpe/dconf2nix
{ lib, ... }:

with lib.hm.gvariant;

{
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      clock-show-seconds = true;
      clock-show-weekday = true;
      show-battery-percentage = true;
      font-name = "Noto Sans 12";
      document-font-name = "Noto Sans 11";
      monospace-font-name = "Noto Sans Mono 10";
      font-antialiasing = "rgba";
      font-hinting = "medium";
      gtk-theme = "adwaita";
      icon-theme = "adwaita";
      toolbar-icons-size = "small";
      toolbar-style = "text";
      toolkit-accessibility = false;
    };

    "org/gnome/desktop/peripherals/touchpad" = {
      click-method = "areas";
      natural-scroll = true;
      send-events = "enabled";
      tap-to-click = true;
      two-finger-scrolling-enabled = true;
    };

    "org/gnome/desktop/wm/keybindings" = {
      close = [ "<Super>c" ];
      switch-to-workspace-1 = [ "<Super>q" ];
      switch-to-workspace-2 = [ "<Super>w" ];
      switch-to-workspace-3 = [ "<Super>e" ];
      switch-to-workspace-4 = [ "<Super>r" ];
      switch-to-workspace-5 = [ "<Super>u" ];
      switch-to-workspace-6 = [ "<Super>i" ];
      switch-to-workspace-7 = [ "<Super>o" ];
      switch-to-workspace-8 = [ "<Super>p" ];
      switch-to-workspace-last = [ "<Super>BackSpace" ];
      toggle-fullscreen = [ "<Super>f" ];
      switch-monitor = [ "XF86Display" ];
    };

    "org/gnome/desktop/wm/preferences" = {
      button-layout = "icon:minimize,maximize,close";
      num-workspaces = 8;
    };

    "org/gnome/mutter" = {
      dynamic-workspaces = false;
      #experimental-features = [ "scale-monitor-framebuffer" ];
      experimental-features = [ "variable-refresh-rate" ];
      workspaces-only-on-primary = true;
    };

    "org/gnome/mutter/keybindings" = {
      switch-monitor = [ "<Super><Alt>p" "XF86Display" ];
    };

    "org/gnome/shell" = {
      disable-user-extensions = false;
      /*
      enabled-extensions = [
        #"caffeine@patapon.info"
        #"system-monitor-next@paradoxxx.zero.gmail.com"
        #"workspace-indicator@gnome-shell-extensions.gcampax.github.com"
      ];
      */
    };

    "org/gnome/settings-daemon/plugins/media-keys" = {
      active = false;
      custom-keybindings = [ "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/" ];
    };

    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
      binding = "<Super>Return";
      command = "alacritty";
      name = "alacritty";
    };

    #"org/virt-manager/virt-manager/connections" = {
    #  autoconnect = [ "qemu:///system" ];
    #  uris = [ "qemu:///system" ];
    #};
  };
}
