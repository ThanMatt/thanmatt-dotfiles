#!/bin/sh

# :: check if any output other than eDP-1 is active
external=$(swaymsg -t get_outputs | jq -r '.[] | select(.name != "eDP-1") | select(.active == true) | .name' | head -1)

swaymsg output eDP-1 disable

if [ -z "$external" ]; then
  # :: lock first, give it time to activate, then suspend
  qs -c noctalia-shell ipc call lockScreen lock
  systemctl suspend
  # sleep 1
fi
