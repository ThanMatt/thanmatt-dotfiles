# :: CURRENTLY NOT BEING USED - USE SWAY'S DEFAULT CONFIG INSTEAD

# ~/.config/sway/scripts/hotplug-monitor.sh
#!/bin/bash

# Give the system a moment to detect the display
sleep 1

# Reload sway to detect new outputs
swaymsg reload

# Optionally, run a custom configuration
# swaymsg output HDMI-A-1 enable
# swaymsg output HDMI-A-1 pos 1920 0
