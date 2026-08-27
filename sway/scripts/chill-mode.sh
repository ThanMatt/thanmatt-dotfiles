#!/bin/sh

# :: Sway half of `chill-mode` -- see fish/functions/chill-mode.fish for the
# :: user-facing command and hypr-new/hyprland.lua (ChillModeRule) for the
# :: Hyprland half.
# ::
# :: Hyprland can flip a windowrule on and off at runtime; sway cannot. A
# :: `for_window` rule CAN be added over IPC, but there is no way to remove one
# :: again short of `swaymsg reload` -- which would also throw away every other
# :: runtime tweak. So this is a daemon instead: it subscribes to sway's window
# :: events and floats each NEW window while the state file says chill mode is
# :: on. Same semantics as the Hyprland rule -- only windows opened while chill
# :: mode is on are floated, already-open ones are left where they are.
# ::
# :: usage: chill-mode.sh [daemon|on|off|toggle|status]
# ::   daemon        -- the listener; started once from ../config (AUTOSTART)
# ::   on|off|toggle -- flip the state file; $mod+alt+f and the `chill-mode`
# ::                    fish function both come through here

state_file="${XDG_CACHE_HOME:-$HOME/.cache}/sway/chill-mode-state"

read_state() {
	[ -r "$state_file" ] && [ "$(cat "$state_file")" = 1 ]
}

write_state() {
	mkdir -p "$(dirname "$state_file")"
	printf '%s' "$1" >"$state_file"
}

announce() {
	if read_state; then
		notify-send -t 2500 "Chill mode" "ON — new windows float"
	else
		notify-send -t 2500 "Chill mode" "OFF — back to tiling"
	fi
}

case "${1:-toggle}" in
daemon)
	# :: Start clean on every sway session, so the state file can't claim ON
	# :: from a previous login while nothing is actually floating. Matches
	# :: ChillModeRule's `enabled = false` default on the Hyprland side.
	write_state 0

	# :: `-m` keeps the subscription open and streams one JSON object per event;
	# :: jq --unbuffered stops those events sitting in the pipe buffer.
	# :: The state file is re-read per window rather than cached, so flipping the
	# :: toggle never needs to signal or restart this daemon.
	swaymsg -t subscribe -m '["window"]' |
		jq --unbuffered -r 'select(.change == "new") | .container.id' |
		while read -r con_id; do
			read_state || continue
			# :: `border pixel 3` chained on for the same reason as
			# :: scripts/scratch-send.sh: default_floating_border does not apply
			# :: to a window that becomes floating AFTER it was mapped, which is
			# :: exactly this case. Keep in sync with ../config.
			swaymsg "[con_id=$con_id] floating enable, border pixel 3" >/dev/null
		done
	;;
on)
	write_state 1
	announce
	;;
off)
	write_state 0
	announce
	;;
toggle)
	if read_state; then write_state 0; else write_state 1; fi
	announce
	;;
status)
	# :: Machine-readable for the fish function's on/off message.
	if read_state; then echo 1; else echo 0; fi
	;;
*)
	echo "usage: chill-mode.sh [daemon|on|off|toggle|status]" >&2
	exit 1
	;;
esac
