#!/bin/bash

tmp_dir="$HOME/.cache/cliphist/thumbs"
mkdir -p "$tmp_dir"

if [ -z "$@" ]; then
  # Generate list with image thumbnails
  cliphist list | while read -r line; do
    id=$(echo "$line" | awk '{print $1}')

    # Check if it's binary/image data
    if echo "$line" | grep -q "binary.*\(png\|jpg\|jpeg\|bmp\|gif\)"; then
      thumb="$tmp_dir/$id.png"

      # Create thumbnail if it doesn't exist
      if [ ! -f "$thumb" ]; then
        echo "$id" | cliphist decode | convert - -resize 48x48 "$thumb" 2>/dev/null
      fi

      # Output with icon
      if [ -f "$thumb" ]; then
        echo -en "$line\0icon\x1f$thumb\n"
      else
        echo "$line"
      fi
    else
      echo "$line"
    fi
  done
else
  # Decode and copy selection
  echo "$@" | cliphist decode | wl-copy
fi
