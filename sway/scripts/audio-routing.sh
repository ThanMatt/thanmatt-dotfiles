#!/bin/bash

# PipeWire Audio Routing Script
# Automatically sets default audio devices based on availability
# Priority: DAC (SA9123) > Built-in speakers for output
# Priority: Audio Interface (PCM2902) for input

# Wait for PipeWire to be fully ready
sleep 2

# Device names
DAC_SINK="alsa_output.usb-SYC_SA9123_USB_Audio-01.analog-stereo"
BUILTIN_SINK="alsa_output.pci-0000_00_1f.3.analog-stereo"
AUDIO_INTERFACE_SOURCE="alsa_input.usb-Burr-Brown_from_TI_USB_Audio_CODEC-00.analog-stereo-input"

# Function to check if a device exists
device_exists() {
    pactl list short "$1" | grep -q "$2"
}

# Set default output (sink) with priority
if device_exists "sinks" "$DAC_SINK"; then
    pactl set-default-sink "$DAC_SINK"
    echo "Default output set to: SA9123 USB Audio (DAC)"
elif device_exists "sinks" "$BUILTIN_SINK"; then
    pactl set-default-sink "$BUILTIN_SINK"
    echo "Default output set to: Built-in Audio (Laptop speakers)"
else
    echo "Warning: No preferred output devices found"
fi

# Set default input (source)
if device_exists "sources" "$AUDIO_INTERFACE_SOURCE"; then
    pactl set-default-source "$AUDIO_INTERFACE_SOURCE"
    echo "Default input set to: PCM2902 Audio Codec (Audio Interface Mic)"
else
    echo "Warning: Audio interface microphone not found, using system default"
fi

# Move existing streams to the new defaults (optional but helpful)
DEFAULT_SINK=$(pactl get-default-sink)
DEFAULT_SOURCE=$(pactl get-default-source)

# Move all sink inputs to the new default sink
pactl list short sink-inputs | while read -r stream; do
    stream_id=$(echo "$stream" | cut -f1)
    pactl move-sink-input "$stream_id" "$DEFAULT_SINK" 2>/dev/null
done

# Move all source outputs to the new default source
pactl list short source-outputs | while read -r stream; do
    stream_id=$(echo "$stream" | cut -f1)
    pactl move-source-output "$stream_id" "$DEFAULT_SOURCE" 2>/dev/null
done

echo "Audio routing completed"
