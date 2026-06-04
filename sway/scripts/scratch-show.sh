#!/bin/sh

# :: Toggle the entire scratch group at once.
# ::   - if any scratch window is currently on screen  -> stash them all
# ::   - if every scratch window is hidden             -> reveal them all
# :: This sidesteps Sway's native one-window-at-a-time scratchpad cycling.

# :: Cleanup pass: a scratch window the user tiled back into a layout
# :: (via floating toggle) is no longer floating, so it has clearly left the
# :: group. Strip its mark so the toggle below stops dragging it back in.
# :: ($floating = every container id that lives under a floating_nodes array;
# ::  scratch windows are floating both while hidden and while shown, so any
# ::  marked window NOT in that set has been tiled out.)
swaymsg -t get_tree | jq -r '
  ([.. | objects | (.floating_nodes? // [])[] | .id]) as $floating
  | .. | objects
  | select(.marks? != null and (.marks | any(startswith("scratch_"))))
  | .id as $id
  | select(($floating | index($id)) | not)
  | .marks[] | select(startswith("scratch_"))' \
| while read -r mark; do
    swaymsg "unmark $mark"
  done

# :: Total windows still carrying a scratch_ mark, anywhere in the tree
total=$(swaymsg -t get_tree | jq '
  [.. | objects | select(.marks? != null) | .marks[] | select(startswith("scratch_"))] | length')

# :: Of those, how many are still hidden inside the __i3_scratch workspace
hidden=$(swaymsg -t get_tree | jq '
  ([.. | objects | select(.name? == "__i3_scratch")] | first)
  | [.. | objects | select(.marks? != null) | .marks[] | select(startswith("scratch_"))] | length')

[ "$total" -eq 0 ] && exit 0

visible=$((total - hidden))

if [ "$visible" -gt 0 ]; then
  # :: Something is on screen -> tuck the whole group away
  swaymsg '[con_mark="^scratch_"] move scratchpad'
else
  # :: All hidden -> bring the whole group forward
  swaymsg '[con_mark="^scratch_"] scratchpad show'
fi
