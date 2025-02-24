#!/bin/bash

xrandr --output eDP-1 --off

xrandr --output DP-1 \
  --mode 3440x1440 \
  --primary \
  --rate 60 \
  --pos 1440x0

xrandr --output HDMI-2 \
  --mode 2560x1440 \
  --rotate left \
  --pos 0x0 \
  --rate 60
