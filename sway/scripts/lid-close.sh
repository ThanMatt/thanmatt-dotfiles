#!/bin/sh

# :: check if any output other than eDP-1 is active
external=$(swaymsg -t get_outputs | jq -r '.[] | select(.name != "eDP-1") | select(.active == true) | .name' | head -1)

swaymsg output eDP-1 disable

if [ -z "$external" ]; then
  # :: Lock BEFORE suspending. The old `qs -c noctalia-shell ipc call lockScreen
  # :: lock` here always failed (quickshell is not installed), and the failure fell
  # :: straight through to `systemctl suspend` — closing the lid on battery
  # :: suspended the machine UNLOCKED. `noctalia msg session lock` returns once the
  # :: lockscreen is up, so no sleep is needed.
  noctalia msg session lock
  systemctl suspend
fi
