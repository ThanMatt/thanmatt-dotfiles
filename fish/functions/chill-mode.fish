function chill-mode --description "toggle floating-only 'chill' mode for every Hyprland window"
    if not pgrep -x Hyprland >/dev/null
        echo "chill-mode: Hyprland isn't running" >&2
        return 1
    end

    set -l mode $argv[1]
    if test -n "$mode"; and not contains -- $mode on off toggle
        echo "usage: chill-mode [on|off|toggle]" >&2
        return 1
    end

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
