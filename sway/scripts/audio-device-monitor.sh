#!/bin/bash

# Monitor PipeWire for device changes and re-run audio routing

# Subscribe to PipeWire events
pactl subscribe | while read -r event; do
    # Check if the event is related to card/sink/source changes
    if echo "$event" | grep -qE "(Card|Sink|Source).*(new|remove|change)"; then
        echo "Audio device change detected: $event"
        # Wait a moment for the device to settle
        sleep 1
        # Re-run audio routing
        ~/.config/sway/scripts/audio-routing.sh
    fi
done
