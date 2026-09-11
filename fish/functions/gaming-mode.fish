function gaming-mode --description "toggle high-sensitivity 'gaming' pointer mode (Sway)"
    set -l mode $argv[1]
    if test -z "$mode"
        set mode toggle
    end
    if not contains -- $mode on off toggle
        echo "usage: gaming-mode [on|off|toggle]" >&2
        return 1
    end

    # :: pgrep rather than $SWAYSOCK so a tmux pane carrying stale session env
    # :: still gets the right answer -- same reason as chill-mode.fish.
    if not pgrep -x sway >/dev/null
        if pgrep -x Hyprland >/dev/null
            echo "gaming-mode: only wired up for sway (Hyprland half not written yet)" >&2
        else
            echo "gaming-mode: sway is not running" >&2
        end
        return 1
    end

    # :: All the logic lives in the script so this and $mod+alt+g can't drift.
    set -l script ~/.config/sway/scripts/gaming-mode.sh
    if not test -x $script
        echo "gaming-mode: $script is missing or not executable" >&2
        return 1
    end

    if not $script $mode >/dev/null
        echo "gaming-mode: $script $mode failed" >&2
        return 1
    end

    if test ($script status) = 1
        echo "Gaming mode ON — pointer sped up"
    else
        echo "Gaming mode OFF — normal pointer speed"
    end
end
