#!/bin/sh

# :: `gaming-mode` -- bumps pointer sensitivity for games and puts it back
# :: after. See fish/functions/gaming-mode.fish for the user-facing command and
# :: $mod+alt+g in ../config for the keybind.
# ::
# :: Unlike chill-mode this needs no daemon: sway's `input` command works at
# :: runtime, so flipping the sensitivity is one IPC call. What it DOES need is
# :: the two accel values to stay in step with the `input type:pointer` block in
# :: ../config -- NORMAL_ACCEL below must match `pointer_accel` there, or turning
# :: gaming mode off would leave the pointer at a speed you never configured.
# ::
# :: pointer_accel takes -1..1; the profile stays `flat` (set in ../config) in
# :: both modes, so this is raw sensitivity with no acceleration curve -- which
# :: is what you want for aiming.
# ::
# :: usage: gaming-mode.sh [on|off|toggle|status|reset]
# ::   on|off|toggle -- $mod+alt+g and the `gaming-mode` fish function
# ::   reset         -- back to normal + clear the state file; exec'd once from
# ::                    ../config so a stale ON can't survive a sway restart

# :: Override from the environment if you want a different feel without editing:
# ::   GAMING_MODE_ACCEL=0.7 gaming-mode.sh on
normal_accel="${GAMING_MODE_NORMAL_ACCEL:--0.5}"
gaming_accel="${GAMING_MODE_ACCEL:-0.4}"

state_file="${XDG_CACHE_HOME:-$HOME/.cache}/sway/gaming-mode-state"

read_state() {
	[ -r "$state_file" ] && [ "$(cat "$state_file")" = 1 ]
}

write_state() {
	mkdir -p "$(dirname "$state_file")"
	printf '%s' "$1" >"$state_file"
}

# :: `type:pointer` is the same identifier ../config configures, so this covers
# :: every mouse without having to name devices that change on replug.
apply() {
	swaymsg "input type:pointer pointer_accel $1" >/dev/null
}

announce() {
	if read_state; then
		notify-send -t 2500 "Gaming mode" "ON — pointer accel $gaming_accel"
	else
		notify-send -t 2500 "Gaming mode" "OFF — pointer accel $normal_accel"
	fi
}

case "${1:-toggle}" in
on)
	write_state 1
	apply "$gaming_accel"
	announce
	;;
off)
	write_state 0
	apply "$normal_accel"
	announce
	;;
toggle)
	if read_state; then
		write_state 0
		apply "$normal_accel"
	else
		write_state 1
		apply "$gaming_accel"
	fi
	announce
	;;
reset)
	# :: Silent on purpose -- this runs at login, where a notification would be
	# :: noise (and would likely beat noctalia's notification daemon anyway).
	write_state 0
	apply "$normal_accel"
	;;
status)
	# :: Machine-readable for the fish function's on/off message.
	if read_state; then echo 1; else echo 0; fi
	;;
*)
	echo "usage: gaming-mode.sh [on|off|toggle|status|reset]" >&2
	exit 1
	;;
esac
