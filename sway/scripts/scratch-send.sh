#!/bin/sh

# :: Send the focused window to the grouped scratchpad.
# :: Each window gets a unique mark (scratch_<nanoseconds>) so scratch-show.sh
# :: can find and toggle the whole group at once instead of cycling one by one.

mark="scratch_$(date +%s%N)"

# :: `border pixel 3` is NOT redundant with `default_floating_border pixel 3` in
# :: ../config. Per man 5 sway, default_floating_border "only applies to windows
# :: that are spawned in floating mode, not windows that become floating
# :: afterwards" — which is exactly what `floating enable` below does. Without it
# :: the client's own preference wins and kitty comes back as border=csd, i.e. no
# :: sway border at all (confirmed via `swaymsg -t get_tree`).
# :: The width must be spelled out: bare `border pixel` means thickness 2, not the
# :: configured default. Keep this in sync with default_border in ../config.
swaymsg "mark --add $mark, floating enable, border pixel 3, move scratchpad"
