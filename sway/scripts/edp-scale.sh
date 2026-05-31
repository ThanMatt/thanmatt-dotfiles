#!/bin/sh

# :: Scale the laptop panel (eDP-1) up when an external display is connected.
# :: When the ThinkPad sits on a stand it's farther away, so 1080p feels small;
# :: when it's the only display (on your lap, up close) we keep it at 1.0.

# :: Tweak these to taste — higher SCALE_EXTERNAL = bigger UI
SCALE_EXTERNAL=1.25
SCALE_SOLO=1.0

apply_scale() {
  # :: any active output other than the laptop panel?
  external=$(swaymsg -t get_outputs | jq -r '.[] | select(.name != "eDP-1") | select(.active == true) | .name' | head -1)

  if [ -n "$external" ]; then
    swaymsg output eDP-1 scale "$SCALE_EXTERNAL"
  else
    swaymsg output eDP-1 scale "$SCALE_SOLO"
  fi
}

# :: set initial state, then react to every output hotplug/change
apply_scale
swaymsg -t subscribe -t output | while read -r _event; do
  apply_scale
done
