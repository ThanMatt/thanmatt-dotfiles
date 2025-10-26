#!/bin/bash
input=$(wofi --dmenu --prompt "=" --cache-file=/dev/null)

if [ -n "$input" ]; then
  result=$(qalc -t "$input" 2>/dev/null)
  if [ -n "$result" ]; then
    echo "$result" | wl-copy
    notify-send "Calculator" "$input = $result" -t 3000
  fi
fi
