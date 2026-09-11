function nightlight --description "toggle the night light (noctalia on Hyprland, gammastep elsewhere)"
    set -l mode $argv[1]
    if test -z "$mode"
        set mode toggle
    end
    if not contains -- $mode on off toggle
        echo "usage: nightlight [on|off|toggle]" >&2
        return 1
    end

    # :: Which daemon actually owns the screen tint depends on the session, so probe
    # :: for the running process rather than trusting a tmux pane's stale env.
    # :: Hyprland dropped wlr-gamma-control-unstable-v1, so gammastep there only logs
    # :: "Zero outputs support gamma adjustment" and tints nothing -- noctalia's own
    # :: night light is what applies the color transform. Driving gammastep.service
    # :: under Hyprland is a silent no-op, which is what this function used to do.
    if pgrep -x noctalia >/dev/null
        __nightlight_noctalia $mode
    else if pgrep -x gammastep >/dev/null; or test -x /usr/bin/gammastep
        __nightlight_gammastep $mode
    else
        echo "nightlight: no night light daemon running (noctalia or gammastep)" >&2
        return 1
    end
end

function __nightlight_wayland_display --description "WAYLAND_DISPLAY of the running session, even from a stale tmux pane"
    if test -n "$WAYLAND_DISPLAY"
        echo $WAYLAND_DISPLAY
        return 0
    end
    # :: tmux panes outlive the compositor they were opened under, so $WAYLAND_DISPLAY
    # :: is often empty or stale here. Read it back from a process that has it right.
    for proc in noctalia Hyprland niri sway
        set -l pid (pgrep -x $proc | head -1)
        if test -n "$pid"; and test -r /proc/$pid/environ
            set -l wl (string replace -rf '^WAYLAND_DISPLAY=' '' -- (tr '\0' '\n' </proc/$pid/environ) | head -1)
            if test -n "$wl"
                echo $wl
                return 0
            end
        end
    end
    return 1
end

function __nightlight_noctalia -a mode --description "night light via the noctalia v5 shell"
    # :: `noctalia msg` reaches the daemon over
    # :: $XDG_RUNTIME_DIR/noctalia-$WAYLAND_DISPLAY.sock, so without a correct
    # :: WAYLAND_DISPLAY it dies with "error: noctalia is not running" while noctalia
    # :: is plainly running.
    set -l wl (__nightlight_wayland_display)
    if test -z "$wl"
        echo "nightlight: noctalia is running but its wayland display could not be found" >&2
        return 1
    end

    # :: These flip the schedule at runtime only -- noctalia does not write the change
    # :: back to ~/.config/noctalia/config.toml, so [nightlight] enabled = true brings
    # :: it back at next login. Edit that key to make "off" stick across restarts.
    # :: `nightlight-force-toggle` is the separate "ignore the clock, tint now" switch.
    switch $mode
        case on
            env WAYLAND_DISPLAY=$wl noctalia msg nightlight-enable >/dev/null; and echo "Night light back on"
        case off
            env WAYLAND_DISPLAY=$wl noctalia msg nightlight-disable >/dev/null; and echo "Night light off (until next login)"
        case toggle
            env WAYLAND_DISPLAY=$wl noctalia msg nightlight-toggle >/dev/null; and echo "Night light toggled"
    end
end

function __nightlight_gammastep -a mode --description "night light via gammastep (sway / niri)"
    if test "$mode" = toggle
        if pgrep -x gammastep >/dev/null
            set mode off
        else
            set mode on
        end
    end

    if test "$mode" = off
        # :: Cover both spawn paths: niri starts gammastep directly
        # :: (spawn-at-startup), elsewhere it comes up as the systemd user unit.
        # :: SIGTERM makes gammastep restore the original ramps on its way out.
        systemctl --user stop gammastep.service 2>/dev/null
        pkill -x gammastep 2>/dev/null
        echo "Night light off"
    else
        # :: The unit needs WAYLAND_DISPLAY in the user manager's env, which niri does
        # :: not export -- fall back to spawning it the way niri's config does.
        systemctl --user start gammastep.service 2>/dev/null
        if not systemctl --user is-active --quiet gammastep.service
            set -l wl (__nightlight_wayland_display)
            env WAYLAND_DISPLAY=$wl gammastep -m wayland >/dev/null 2>&1 &
            disown
        end
        echo "Night light back on"
    end
end
