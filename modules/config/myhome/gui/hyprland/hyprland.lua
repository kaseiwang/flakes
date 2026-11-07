hl.config({
    general = {
        border_size = 0,
        gaps_in = 1,
        gaps_out = 0,
    },
})

hl.bind("SUPER + Return", hl.dsp.exec_cmd("uwsm app -- ghostty"))

hl.bind("SUPER + 1", hl.dsp.exec_cmd("uwsm app -- chromium"))
hl.bind("SUPER + 2", hl.dsp.exec_cmd("uwsm app -- code"))
hl.bind("SUPER + SPACE", hl.dsp.exec_cmd("vicinae toggle"))

hl.bind("SUPER + q", hl.dsp.focus({ workspace = "1" }))
hl.bind("SUPER + w", hl.dsp.focus({ workspace = "2" }))
hl.bind("SUPER + e", hl.dsp.focus({ workspace = "3" }))
hl.bind("SUPER + r", hl.dsp.focus({ workspace = "4" }))
hl.bind("SUPER + t", hl.dsp.focus({ workspace = "5" }))
hl.bind("SUPER + y", hl.dsp.focus({ workspace = "6" }))
hl.bind("SUPER + u", hl.dsp.focus({ workspace = "7" }))
hl.bind("SUPER + i", hl.dsp.focus({ workspace = "8" }))
hl.bind("SUPER + o", hl.dsp.focus({ workspace = "9" }))

hl.bind("SUPER + h", hl.dsp.focus({ direction = "left" }))
hl.bind("SUPER + l", hl.dsp.focus({ direction = "right" }))
hl.bind("SUPER + k", hl.dsp.focus({ direction = "up" }))
hl.bind("SUPER + j", hl.dsp.focus({ direction = "down" }))

hl.bind("SUPER + SHIFT + h", hl.dsp.window.move({ direction = "left" }))
hl.bind("SUPER + SHIFT + l", hl.dsp.window.move({ direction = "right" }))
hl.bind("SUPER + SHIFT + k", hl.dsp.window.move({ direction = "up" }))
hl.bind("SUPER + SHIFT + j", hl.dsp.window.move({ direction = "down" }))

hl.bind("SUPER + c", hl.dsp.window.close())
hl.bind("SUPER + f", hl.dsp.window.fullscreen({ action = "toggle" }))
hl.bind("SUPER + SHIFT + f", hl.dsp.window.float({ action = "toggle" }))
hl.bind("SUPER + r", hl.dsp.submap("resize"))

hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { repeating = true })
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"), { repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"))
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"))
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl s 10%+"), { repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl s 10%-"), { repeating = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"))
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"))
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"))

hl.bind("CTRL + SUPER + l", hl.dsp.exec_cmd("hyprlock"))
hl.bind("CTRL + SUPER + escape", hl.dsp.submap("logout"))

hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace"
})
