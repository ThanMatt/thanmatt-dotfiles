#!/bin/bash

# Turn off external displays
xrandr --output DP-1 --off
xrandr --output HDMI-2 --off

# Enable laptop display with its native resolution
xrandr --output eDP-1 --mode 1366x768 --primary --pos 0x0
