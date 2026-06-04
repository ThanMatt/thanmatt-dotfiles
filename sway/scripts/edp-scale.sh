#!/bin/sh

# :: Scale the laptop panel (eDP-1) up when an external display is connected.
# :: When the ThinkPad sits on a stand it's farther away, so 1080p feels small;
# :: when it's the only display (on your lap, up close) we keep it at 1.0.

# :: Tweak these to taste — higher SCALE_EXTERNAL = bigger UI
SCALE_EXTERNAL=1.25
SCALE_SOLO=1.0

apply_scale() {
  outputs=$(swaymsg -t get_outputs)

  # :: any active output other than the laptop panel?
  external=$(echo "$outputs" | jq -r '.[] | select(.name != "eDP-1") | select(.active == true) | .name' | head -1)

  if [ -n "$external" ]; then
    target=$SCALE_EXTERNAL
  else
    target=$SCALE_SOLO
  fi

  current=$(echo "$outputs" | jq -r '.[] | select(.name == "eDP-1") | .scale')

  # :: only touch the output when the scale actually needs to change — re-applying
  # :: the same scale emits another output event and feeds back into our loop,
  # :: spinning swaymsg/jq forever (pegs a core). awk handles float compare.
  [ "$(awk -v a="$current" -v b="$target" 'BEGIN { print (a == b) }')" = "1" ] && return

  swaymsg output eDP-1 scale "$target"
}

# :: set initial state, then react to every output hotplug/change
apply_scale

pending=""
swaymsg -m -t subscribe '["output"]' | while read -r _event; do
  # :: coalesce bursts, then re-check at a few intervals: unplug settles fast,
  # :: but replug needs EDID/mode negotiation and can land after the first check
  [ -n "$pending" ] && kill "$pending" 2>/dev/null
  ( sleep 0.3; apply_scale; sleep 0.7; apply_scale; sleep 1.0; apply_scale ) &
  pending=$!
done
