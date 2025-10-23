#!/bin/bash

# Path to emoji list (you can customize this)
EMOJI_LIST="$HOME/.config/wofi/emojis.txt"

# Select emoji with wofi and copy to clipboard
selected=$(cat "$EMOJI_LIST" | wofi --dmenu -i -p "Select emoji" | awk '{print $1}')

if [ -n "$selected" ]; then
  echo -n "$selected" | wl-copy
  notify-send "Emoji copied" "$selected"
fi
