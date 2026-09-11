# Generated via dconf2nix: https://github.com/gvolpe/dconf2nix
{ lib, ... }:

with lib.hm.gvariant;

{
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      clock-show-seconds = true;
      clock-show-weekday = true;
      show-battery-percentage = true;
      document-font-name = "Noto Sans 11";
      monospace-font-name = "monospace 10";
      font-antialiasing = "rgba";
      font-hinting = "slight";
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
      switch-monitor = [
        "<Super><Alt>p"
        "XF86Display"
      ];
    };

    "org/gnome/shell/extensions/caffeine" = {
      indicator-position-max = 1;
      toggle-state = true;
    };

    "org/gnome/shell/extensions/kimpanel" = {
      vertical = false;
    };

    "org/gnome/shell/extensions/system-monitor-next-applet" = {
      center-display = false;
      compact-display = true;
      icon-display = true;
      left-display = false;
      monitors = map builtins.toJSON [
        {
          uuid = "42cf660bfbd5ebba6f206bfd6aa43f00";
          type = "cpu";
          device = "all";
          display = true;
          style = "graph";
          graph-width = 100;
          refresh-time = 1500;
          show-text = true;
          show-menu = true;
          colors = {
            user = "#0072b3";
            system = "#0092e6";
            nice = "#00a3ff";
            iowait = "#002f3d";
            other = "#001d26";
          };
        }
        {
          uuid = "e11b2121405a9fc13b8e57fb6aa43f00";
          type = "freq";
          device = "all";
          display = true;
          style = "digit";
          graph-width = 100;
          refresh-time = 1500;
          show-text = false;
          show-menu = false;
          colors = {
            freq = "#001d26";
          };
          display-mode = "max";
        }
        {
          uuid = "27c08d65a308e2a102f39eca6aa43f00";
          type = "memory";
          device = "default";
          display = true;
          style = "digit";
          graph-width = 100;
          refresh-time = 5000;
          show-text = true;
          show-menu = true;
          colors = {
            program = "#00b35b";
            buffer = "#00ff82";
            cache = "#aaf5d0";
          };
        }
        {
          uuid = "6e1b706b1b1d18c58346e0166aa43f00";
          type = "swap";
          device = "default";
          display = false;
          style = "graph";
          graph-width = 100;
          refresh-time = 5000;
          show-text = true;
          show-menu = true;
          colors = {
            used = "#8b00c3";
          };
        }
        {
          uuid = "d27b795734bf053bae7a1aa06aa43f00";
          type = "net";
          device = "all";
          display = true;
          style = "digit";
          graph-width = 100;
          refresh-time = 1000;
          show-text = true;
          show-menu = true;
          colors = {
            down = "#fce94f";
            downerrors = "#ff6e00";
            up = "#fb74fb";
            uperrors = "#e0006e";
            collisions = "#ff0000";
          };
          speed-in-bits = false;
        }
        {
          uuid = "2f0ca4483543ef5407cfa6a76aa43f00";
          type = "disk";
          device = "all";
          display = false;
          style = "graph";
          graph-width = 100;
          refresh-time = 2000;
          show-text = true;
          show-menu = true;
          colors = {
            read = "#c65000";
            write = "#ff6700";
          };
        }
        {
          uuid = "5a0c82a9407aa329fbe16e0f6aa43f00";
          type = "gpu";
          device = "0";
          display = true;
          style = "digit";
          graph-width = 100;
          refresh-time = 5000;
          show-text = true;
          show-menu = false;
          colors = {
            used = "#00b35b";
            memory = "#00ff82";
          };
        }
        {
          uuid = "559191943d887f8097a8d7646aa43f00";
          type = "thermal";
          device = "";
          display = false;
          style = "graph";
          graph-width = 100;
          refresh-time = 5000;
          show-text = true;
          show-menu = true;
          colors = {
            tz0 = "#f2002e";
          };
          fahrenheit-unit = false;
          threshold = 0;
        }
        {
          uuid = "908e44caa80aed7cf6877bce6aa43f00";
          type = "fan";
          device = "";
          display = false;
          style = "graph";
          graph-width = 100;
          refresh-time = 5000;
          show-text = true;
          show-menu = true;
          colors = {
            fan0 = "#f2002e";
          };
        }
        {
          uuid = "7e6bb106c322864d7120fb2d6aa43f00";
          type = "battery";
          device = "default";
          display = false;
          style = "digit";
          graph-width = 100;
          refresh-time = 5000;
          show-text = true;
          show-menu = false;
          colors = {
            batt0 = "#f2002e";
          };
          time = false;
          hidesystem = false;
        }
      ];
      move-clock = false;
      settings-schema-version = 2;
      show-tooltip = false;
    };

    "org/gnome/settings-daemon/plugins/media-keys" = {
      active = false;
      custom-keybindings = [
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
      ];
    };

    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
      binding = "<Super>Return";
      command = "ghostty";
      name = "Ghostty";
    };

    #"org/virt-manager/virt-manager/connections" = {
    #  autoconnect = [ "qemu:///system" ];
    #  uris = [ "qemu:///system" ];
    #};
  };
}
