#!/bin/sh

# :: Hyprland port of the Sway lid-close handler.
# :: Fired on lid CLOSE (bindl switch:on:Lid Switch -> this script).
# ::
# ::   - Always disable the laptop panel (eDP-1).
# ::   - If an EXTERNAL monitor is active -> clamshell mode, stay awake.
# ::   - If eDP-1 is the only display     -> lock (Noctalia) then suspend.
# ::
# :: Lid OPEN re-enables eDP-1 from hyprland.lua (bindl switch:off:Lid Switch).

# :: Any currently-active output other than eDP-1.
# :: `hyprctl monitors` lists only active/enabled outputs, so a non-eDP-1 hit
# :: here means an external display is connected and on.
external=$(hyprctl -j monitors | jq -r '.[] | select(.name != "eDP-1") | .name' | head -1)

# :: `hyprctl keyword` is a no-op under the Lua config parser — it answers
# :: "keyword can't work with non-legacy parsers. Use eval." — so drive the
# :: monitor through `hyprctl eval` + the Lua monitor spec instead.
hyprctl eval 'hl.monitor({ output = "eDP-1", disabled = true })'

if [ -z "$external" ]; then
  # :: No external display -> lock with hyprlock first so it is up before we go
  # :: down, then suspend. hypridle's before_sleep_cmd is a backstop, but locking
  # :: explicitly here avoids any race on slow suspends. `pidof` guard = no 2nd
  # :: instance. Noctalia's lockOnSuspend is off (settings.json) to avoid a
  # :: competing lock screen.
  pidof hyprlock || hyprlock &
  systemctl suspend
fi
