#!/bin/sh

# :: Send the focused window to the grouped scratchpad.
# :: Each window gets a unique mark (scratch_<nanoseconds>) so scratch-show.sh
# :: can find and toggle the whole group at once instead of cycling one by one.

mark="scratch_$(date +%s%N)"

swaymsg "mark --add $mark, floating enable, move scratchpad"
