{ lib, pkgs }:
let
  # The packaged UWSM login entry starts hyprland.desktop.
  sessionTarget = "wayland-session@hyprland.desktop.target";
  network = interface: label: {
    inherit interface;
    format = "${label} ↓{bandwidthDownBytes} ↑{bandwidthUpBytes}";
    format-linked = "";
    format-disconnected = "";
    format-disabled = "";
    tooltip-format = "{ifname}: {ipaddr}";
  };
in
{
  # The parent module applies the Hyprland enable condition to this configuration.
  programs.waybar = {
    enable = true;
    systemd = {
      enable = true;
      targets = [ sessionTarget ];
    };
    settings.mainBar = {
      layer = "top";
      position = "bottom";
      modules-left = [ "hyprland/workspaces" ];
      modules-right = [
        "cpu"
        "custom/gpu"
        "temperature"
        "memory"
        "network#wifi"
        "network#ethernet"
        "network#usb1"
        "network#usb2"
        "network#usb3"
        "battery"
        "pulseaudio"
        "clock"
      ];

      "hyprland/workspaces" = {
        format = "{icon}";
        format-icons = lib.listToAttrs (
          lib.imap1
            (id: key: {
              name = toString id;
              value = "${toString id}: ${key}";
            })
            [
              "q"
              "w"
              "e"
              "r"
              "t"
              "y"
              "u"
              "i"
              "o"
            ]
        );
        sort-by-number = true;
      };
      cpu = {
        format = "⌬ {usage}%";
      };
      "custom/gpu" = {
        # amdgpu iGPU: address by PCI path, as cardN is not stable.
        exec = "cat /sys/devices/pci0000:00/0000:00:08.1/0000:35:00.0/gpu_busy_percent";
        # Custom modules run exec once without an interval; match cpu's 10s.
        interval = 10;
        format = "GPU {}%";
      };
      temperature = {
        # CPU k10temp device: avoid the unstable hwmonN index.
        hwmon-path-abs = "/sys/devices/pci0000:00/0000:00:18.3/hwmon";
        input-filename = "temp1_input";
        format = "{temperatureC}°";
      };
      memory = {
        format = "≣ {used:0.1f} GiB";
      };
      "network#wifi" = network "wl*" "";
      "network#ethernet" = network "enp2s0" "";
      "network#usb1" = network "en*u1" "U1:";
      "network#usb2" = network "en*u2" "U2:";
      "network#usb3" = network "en*u3" "U3:";
      battery = {
        format = " {capacity}%";
      };
      # PulseAudio/PipeWire and workspaces update on events, without polling.
      pulseaudio = {
        format = " {volume}%";
        format-muted = " MUTE";
      };
      clock =
        let
          long = "{:%Y/%m/%d %A %H:%M:%S}";
        in
        {
          format = "{:%I:%M %p}";
          # Click toggles to the long format; GTK3 tooltips have a fixed hover delay.
          format-alt = long;
          tooltip-format = long;
          # Default is 60s, which freezes the long format's %S field at :00.
          interval = 1;
        };
    };
    # Keep the packaged stylesheet; it has no rule for custom/gpu.
    style = ''
      @import url("${pkgs.waybar}/etc/xdg/waybar/style.css");

      #custom-gpu {
        padding: 0 10px;
        background-color: #00cec9;
        color: #000000;
      }
    '';
  };

  # Remove the generic tray.target startup entry added by Home Manager.
  systemd.user.services.waybar.Install.WantedBy = lib.mkForce [ sessionTarget ];
}
