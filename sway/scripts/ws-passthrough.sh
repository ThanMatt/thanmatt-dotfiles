#!/usr/bin/env bash
# :: Ctrl+$mod+h / Ctrl+$mod+l -- prev/next workspace, with Emacs passthrough.
# ::
# :: Sway can't make a binding conditional on the focused app, so sway keeps
# :: the binding and runs this. When the coding Emacs is focused it gets first
# :: go: `my/sway-workspace-passthrough' (doom/+linux.el) steps its Doom
# :: workspace and answers `handled'. At the first/last Doom workspace it
# :: answers `pass' instead and sway moves on -- so sway and Doom workspaces
# :: behave like one strip, and you can never get stuck inside Emacs.
# ::
# :: Ways out that skip Emacs entirely (see ../config):
# ::   - Ctrl+$mod+Shift+h/l   plain sway prev/next, never asks Emacs
# ::   - $mod+a, then h/l      focus parent -- a container isn't an Emacs
# ::                           window, so the next press goes to sway
# ::   - $mod+N                always sway-only
# ::
# :: Wrinkles:
# ::
# :: 1. Each GUI Emacs has its own socket: the first holds "server" (Doom
# ::    starts it), any later one "server<PID>" (doom/+linux.el, and magit's
# ::    with-editor uses the same name). So look up "server<PID>" for the
# ::    focused window first and fall back to "server". The notes daemon holds
# ::    "notes" -- see emacs-float.sh; its frame (title "notes") is skipped
# ::    here without a round trip, and Emacs double-checks the window's PID
# ::    against its own anyway.
# ::
# :: 2. `timeout' so a blocked Emacs (long GC, synchronous LSP call) can't eat
# ::    the keypress -- after 0.3 s sway handles it. The queued eval may still
# ::    run once Emacs is free, moving it one Doom workspace in the background.
# ::
# :: 3. Cost is roughly 15-30 ms per press (swaymsg + jq, plus emacsclient when
# ::    Emacs is focused).

set -u

case "${1:-}" in
    prev) sway_cmd="workspace prev_on_output" ;;
    next) sway_cmd="workspace next_on_output" ;;
    *)    echo "usage: $0 prev|next" >&2; exit 2 ;;
esac

dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/emacs"

pid=$(swaymsg -t get_tree | jq -r '
    recurse(.nodes[]?, .floating_nodes[]?)
    | select(.focused and .app_id == "emacs" and .name != "notes")
    | .pid' 2>/dev/null)

socket="$dir/server$pid"
[ -S "$socket" ] || socket="$dir/server"

if [ -n "$pid" ] && [ -S "$socket" ]; then
    verdict=$(timeout 0.3 emacsclient -s "$socket" \
        -e "(my/sway-workspace-passthrough '$1 $pid)" 2>/dev/null)
    [ "$verdict" = handled ] && exit 0
fi

exec swaymsg "$sway_cmd" >/dev/null
