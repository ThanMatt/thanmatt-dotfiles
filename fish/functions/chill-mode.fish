function chill-mode --description "toggle floating-only 'chill' mode for every new window (Hyprland or Sway)"
    set -l mode $argv[1]
    if test -z "$mode"
        set mode toggle
    end
    if not contains -- $mode on off toggle
        echo "usage: chill-mode [on|off|toggle]" >&2
        return 1
    end

    # :: Same command on both compositors, but the mechanism differs -- see the
    # :: helpers below. pgrep rather than $HYPRLAND_INSTANCE_SIGNATURE/$SWAYSOCK
    # :: so a tmux pane carrying stale session env still picks the right one.
    if pgrep -x Hyprland >/dev/null
        __chill_mode_hyprland $mode
    else if pgrep -x sway >/dev/null
        __chill_mode_sway $mode
    else
        echo "chill-mode: neither Hyprland nor sway is running" >&2
        return 1
    end
end

function __chill_mode_hyprland --argument-names mode
    # :: Actual toggle lives in hyprland.lua (ChillModeRule / ChillModeSet /
    # :: ChillModeToggle) -- `hyprctl eval` runs Lua in the live config's own
    # :: state, which is also what SUPER+ALT+F calls in-process. Both paths
    # :: write the same state file, so this stays in sync either way.
    set -l call ChillModeToggle\(\)
    switch $mode
        case on
            set call ChillModeSet\(true\)
        case off
            set call ChillModeSet\(false\)
    end

    if not hyprctl eval "$call" >/dev/null
        echo "chill-mode: hyprctl eval failed -- is hyprland.lua reloaded? (hyprctl reload)" >&2
        return 1
    end

    set -l state_file ~/.cache/hypr/chill-mode-state
    if test -e $state_file; and test (cat $state_file) = 1
        echo "Chill mode ON — new windows float"
    else
        echo "Chill mode OFF — back to tiling"
    end
end

function __chill_mode_sway --argument-names mode
    # :: Sway can add a `for_window` rule over IPC but never remove one without
    # :: a full reload, so there is no rule to flip -- scripts/chill-mode.sh runs
    # :: a window-event listener that floats new windows while the state file
    # :: says on. $mod+alt+f calls the same script, so both paths stay in sync.
    set -l script ~/.config/sway/scripts/chill-mode.sh
    if not test -x $script
        echo "chill-mode: $script is missing or not executable" >&2
        return 1
    end

    if not $script $mode >/dev/null
        echo "chill-mode: $script $mode failed" >&2
        return 1
    end

    if test ($script status) = 1
        echo "Chill mode ON — new windows float"
    else
        echo "Chill mode OFF — back to tiling"
    end
end
