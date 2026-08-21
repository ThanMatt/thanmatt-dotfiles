#!/bin/sh

# :: Dim / restore the external panel's backlight over DDC/CI, driven by the
# :: `[idle.behavior.dim]` custom action in noctalia-v5/config.toml.
# ::
# :: Why ddcutil and not brightnessctl: this machine has NO sysfs backlight
# :: (`/sys/class/backlight` is empty) because the only active output is DP-1,
# :: an external LG UltraGear. brightnessctl and `noctalia msg brightness-*`
# :: are both sysfs-only, so they are silent no-ops here — DDC/CI over the
# :: DisplayPort i2c bus is the only way to reach this panel's backlight.
# ::
# :: The pre-dim level is saved to XDG_RUNTIME_DIR rather than hardcoded in the
# :: config, so restoring cannot clobber a brightness you set by hand between
# :: idle cycles. State lives in /run, so a reboot forgets it (correct: the
# :: monitor comes back at its own stored level anyway).

DIM_LEVEL=25
STATE="${XDG_RUNTIME_DIR:-/tmp}/panel-dim.brightness"

# :: No DDC-capable display (undocked, monitor off) — nothing to do. Every
# :: ddcutil call below would fail anyway, and the idle action would log noise.
ddcutil detect --brief >/dev/null 2>&1 || exit 0

case "$1" in
  dim)
    # :: `--brief` prints `VCP 10 C <current> <max>`; field 4 is the current value.
    current=$(ddcutil getvcp 10 --brief 2>/dev/null | awk '/^VCP 10/ { print $4 }')

    # :: Bail if the read failed, and don't overwrite saved state when we're
    # :: already at or below DIM_LEVEL — a second dim would otherwise record the
    # :: dimmed value and restore would leave the panel dark.
    [ -n "$current" ] || exit 0
    [ "$current" -le "$DIM_LEVEL" ] && exit 0

    printf '%s\n' "$current" > "$STATE"
    ddcutil setvcp 10 "$DIM_LEVEL" >/dev/null 2>&1
    ;;
  restore)
    # :: No state file means we never dimmed (or already restored) — leave the
    # :: panel alone rather than guessing a level.
    [ -f "$STATE" ] || exit 0

    saved=$(cat "$STATE")
    rm -f "$STATE"

    [ -n "$saved" ] || exit 0
    ddcutil setvcp 10 "$saved" >/dev/null 2>&1
    ;;
  *)
    echo "usage: ${0##*/} {dim|restore}" >&2
    exit 1
    ;;
esac
