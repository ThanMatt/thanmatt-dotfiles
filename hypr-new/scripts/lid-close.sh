#!/bin/sh

# :: Hyprland port of the Sway lid-close handler.
# :: Fired on lid CLOSE (bindl switch:on:Lid Switch -> this script).
# ::
# ::   - Always disable the laptop panel (eDP-1).
# ::   - If an EXTERNAL monitor is active -> clamshell mode, stay awake.
# ::   - If eDP-1 is the only display     -> lock (Noctalia) then suspend.
# ::
# :: Lid OPEN re-enables eDP-1 from hyprland.lua (bindl switch:off:Lid Switch).

LOG="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/clamshell.log"
mkdir -p "$(dirname "$LOG")"
log() { printf '%s lid-close: %s\n' "$(date '+%F %T')" "$1" >>"$LOG"; }

# :: Any currently-active output other than eDP-1.
# :: `hyprctl monitors` lists only active/enabled outputs, so a non-eDP-1 hit
# :: here means an external display is connected and on.
# ::
# :: FALLBACK/HEADLESS-* are excluded deliberately. When the last real output
# :: goes away Hyprland enters its "unsafe state" and substitutes a synthetic
# :: FALLBACK output (hyprland 0.56). That only shows up on the monitor-watch.py
# :: path — where eDP-1 is ALREADY disabled, so unplugging the external leaves
# :: zero real outputs — and counting it as an external display is what kept a
# :: closed-lid unplug awake forever. On the plain lid-close path this check
# :: runs before eDP-1 is disabled, so it never sees the unsafe state.
monitors=$(hyprctl -j monitors)
external=$(printf '%s' "$monitors" | jq -r '
    .[]
    | select(.name != "eDP-1")
    | select(.name | test("^(FALLBACK|HEADLESS)") | not)
    | .name' | head -1)

log "active=[$(printf '%s' "$monitors" | jq -r '[.[].name] | join(",")')] external=[$external]"

# :: `hyprctl keyword` is a no-op under the Lua config parser — it answers
# :: "keyword can't work with non-legacy parsers. Use eval." — so drive the
# :: monitor through `hyprctl eval` + the Lua monitor spec instead.
hyprctl eval 'hl.monitor({ output = "eDP-1", disabled = true })'

if [ -z "$external" ]; then
  log "no external -> lock + suspend"
  # :: No external display -> lock with hyprlock first so it is up before we go
  # :: down, then suspend. hypridle's before_sleep_cmd is a backstop, but locking
  # :: explicitly here avoids any race on slow suspends. `pidof` guard = no 2nd
  # :: instance. Noctalia's lockOnSuspend is off (settings.json) to avoid a
  # :: competing lock screen.
  pidof hyprlock || hyprlock &
  systemctl suspend
else
  log "external present -> clamshell, staying awake"
fi
