#!/usr/bin/env bash
# :: $mod+n -- open a frame on the "notes" Emacs as a floating window on the
# :: CURRENT sway workspace. The frame is a normal window that sway floats via
# :: the `for_window' rule in ../config, so $mod+q kills it for good.
# ::
# :: THE TWO-INSTANCE SPLIT (read this before changing anything here):
# ::
# :: Two Emacsen run on this machine on purpose.
# ::   - "notes"  -- started by ../config as `emacs --daemon=notes'. Light: no
# ::                 lsp-mode, no vterm. This is the scratchpad $mod+n opens.
# ::   - coding   -- a separate, heavier instance started from the Noctalia
# ::                 launcher. Owns the LSP servers, vterms and Claude buffers.
# ::
# :: Naming the daemon is what makes them addressable. It pins the socket to
# :: $sockdir/notes, so this script targets ONE known process. It used to scan
# :: for "the plain `server' socket, else the newest one that answers" -- but
# :: which process holds "server" is just whoever started first (server.el
# :: renames later ones to "server<PID>"), so $mod+n landed on the coding
# :: instance or the daemon depending on login timing. That is what made notes
# :: frames show up with the wrong buffers in them.
# ::
# :: `(daemonp)' also returns "notes" inside that Emacs, which is how
# :: doom/config.el gives it its own recentf / savehist / saveplace / undo /
# :: workspace files. Renaming the daemon means renaming it in all three places:
# :: here, ../config, and doom/config.el.
# ::
# :: Other wrinkles this handles:
# ::
# :: 1. Doom sets `frame-title-format', so every frame's title is identical and
# ::    sway has nothing to match on. The `title' FRAME PARAMETER outranks
# ::    `frame-title-format', so -F pins this one frame's title to $FRAME_TITLE
# ::    and the for_window rule keys off that. Don't rename it in one place
# ::    without renaming it in the other.
# ::
# :: 2. `-n' matters. Without it `-c' blocks until the frame is deleted, so every
# ::    press leaves an emacsclient parked for the life of the window.
# ::
# :: 3. No Doom-workspace juggling. This used to eval `my/notes-workspace' in the
# ::    new frame, because a frame on the SHARED coding instance would otherwise
# ::    inherit whatever perspective was last active. A dedicated process has one
# ::    job and one buffer list, so per-frame perspectives buy nothing here.

set -u

FRAME_TITLE=notes

# :: Must match `--daemon=<name>' in ../config.
SERVER_NAME=notes

# :: Pressing the bind again focuses the existing frame rather than stacking up
# :: duplicates. Set to 0 if you'd rather get a fresh frame every press.
FOCUS_EXISTING=1

sockdir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/emacs"
socket="$sockdir/$SERVER_NAME"

if [ "$FOCUS_EXISTING" = 1 ] && command -v jq >/dev/null 2>&1; then
    if swaymsg -t get_tree \
        | jq -e --arg t "$FRAME_TITLE" \
            'recurse | select(.app_id? == "emacs" and .name? == $t)' >/dev/null 2>&1
    then
        exec swaymsg "[app_id=\"emacs\" title=\"^${FRAME_TITLE}\$\"] focus"
    fi
fi

# :: `-e' makes emacsclient read EVERY remaining argument as elisp, so file
# :: arguments can't just be appended -- they'd be evaluated. Turn them into
# :: `find-file' forms instead.
forms=()
for f in "$@"; do
    forms+=("(find-file \"$(realpath -- "$f")\")")
done

# :: Start the named daemon if it isn't up (first press after a crash, or if the
# :: sway `exec' failed). Deliberately NOT `emacsclient -a ""' -- that documents
# :: itself as running a bare `emacs --daemon', which would claim the unnamed
# :: "server" socket and re-create exactly the ambiguity this script exists to
# :: avoid. Start it by name and wait for the socket to appear instead.
if ! emacsclient -s "$socket" -e t >/dev/null 2>&1; then
    emacs --daemon="$SERVER_NAME" >/dev/null 2>&1
    for _ in $(seq 1 50); do
        emacsclient -s "$socket" -e t >/dev/null 2>&1 && break
        sleep 0.2
    done
fi

if [ "${#forms[@]}" -gt 0 ]; then
    exec emacsclient -s "$socket" -c -n -F "((title . \"$FRAME_TITLE\"))" \
         -e "${forms[@]}"
fi

# :: No files to open -- `-e' needs at least one form, so just make the frame.
exec emacsclient -s "$socket" -c -n -F "((title . \"$FRAME_TITLE\"))"
