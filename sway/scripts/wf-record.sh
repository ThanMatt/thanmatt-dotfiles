#!/bin/sh

# :: Region screen recording -- the macOS Cmd+Shift+5 equivalent. Bound to
# :: $mod+shift+r in ../config and in ../../hypr-new/hyprland.lua: first press
# :: picks a region with slurp and starts recording, second press stops it and
# :: puts the file path on the clipboard.
# ::
# :: Lives under sway/scripts but is WM-agnostic and shared by both configs, the
# :: same way audio-routing.sh and calc.sh are -- everything here is wlroots
# :: protocol (slurp / wf-recorder / wl-copy), and only `output` mode needs to
# :: ask the compositor anything, which focused_output() handles.
# ::
# :: Neither WM can *signal* a process from a keybind, only launch one, so a
# :: single key cannot both start and stop a long-running recorder -- hence the
# :: pidfile toggle, same shape as chill-mode.sh's state file.
# ::
# :: usage: wf-record.sh [toggle|region|output|stop|status] [audio]
# ::   toggle -- what the keybind calls; region if idle, stop if recording
# ::   region -- always start a new region recording (no-op if already running)
# ::   output -- record the whole focused output instead of a region
# ::   audio  -- optional 2nd arg; also captures the default PipeWire sink

dir="$HOME/Videos/Recordings"
# :: PID, not state: XDG_RUNTIME_DIR is cleared on logout, so a stale pidfile
# :: can't outlive the session that owned the process.
run_dir="${XDG_RUNTIME_DIR:-/tmp}"
pid_file="$run_dir/wf-record.pid"
path_file="$run_dir/wf-record.path"

# :: This box is an NVIDIA card. nvidia-vaapi-driver is DECODE-only, so the
# :: usual wayland recipe (-c h264_vaapi -d /dev/dri/renderD128) fails here and
# :: wf-recorder's own default (libx264) isn't in Fedora's ffmpeg-free either.
# :: NVENC is what's left, and it needs an explicit pixel format because
# :: wf-recorder hands it the compositor's BGRx buffers otherwise.
encoder="h264_nvenc"
pix_fmt="yuv420p"

# :: wf-recorder takes an output NAME (-o), which both compositors report, but
# :: through their own IPC. HYPRLAND_INSTANCE_SIGNATURE is set by Hyprland for
# :: every client it spawns; under sway it's absent and SWAYSOCK is what's set.
focused_output() {
	if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
		hyprctl -j monitors | jq -r '.[] | select(.focused) | .name'
	else
		swaymsg -t get_outputs | jq -r '.[] | select(.focused) | .name'
	fi
}

recording() {
	[ -r "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null
}

start() {
	recording && return 0

	# :: Read both args off before `set --` below overwrites the positionals.
	mode=$1
	want_audio=$2

	# :: The args are built with `set --` rather than interpolated into a string
	# :: because slurp's geometry CONTAINS A SPACE ("x,y WxH") and has to reach
	# :: wf-recorder as a single argv entry. Unquoted, the shell splits it and
	# :: wf-recorder sees only "x,y" -- it then logs "Bad geometry" and silently
	# :: records the whole output, which looks like the crop being ignored.
	if [ "$mode" = output ]; then
		set -- -o "$(focused_output)"
	else
		# :: slurp writes "x,y WxH"; empty means Escape / right-click, i.e. the
		# :: user backed out, so don't start anything.
		region=$(slurp) || exit 0
		[ -n "$region" ] || exit 0
		set -- -g "$region"
	fi

	[ "$want_audio" = audio ] && set -- "$@" -a

	mkdir -p "$dir"
	out="$dir/$(date +'%Y-%m-%d-%H%M%S')_wf.mp4"

	# :: setsid so the recorder survives the transient shell the WM spawns for a
	# :: keybind -- otherwise it dies with its parent the moment the key is released.
	# ::
	# :: The pid is written by the inner shell rather than taken from `$!`,
	# :: because setsid forks whenever its caller is already a process group
	# :: leader -- so `$!` is sometimes setsid's own (immediately dead) pid
	# :: instead of the recorder's. Whether it forks depends on the job-control
	# :: state of whatever invoked this, which is not something to rely on: get
	# :: it wrong and stop() signals nothing while the recorder runs forever.
	# :: `exec` keeps $$ pointing at the process that replaces the inner shell.
	setsid sh -c 'echo $$ >"$1"; shift; exec wf-recorder "$@"' sh \
		"$pid_file" "$@" -c "$encoder" -x "$pix_fmt" -f "$out" \
		>"$run_dir/wf-record.log" 2>&1 &

	printf '%s' "$out" >"$path_file"

	notify-send -t 2500 "Recording" "Started — Mod+Shift+R again to stop"
}

stop() {
	recording || {
		notify-send -t 2000 "Recording" "Nothing is recording"
		return 0
	}

	# :: SIGINT, never SIGTERM/SIGKILL: wf-recorder traps INT to flush the
	# :: encoder and write the MP4 moov atom. Killed any harder, the file is
	# :: unplayable.
	kill -INT "$(cat "$pid_file")" 2>/dev/null

	# :: Give it a moment to finalise before advertising the path.
	i=0
	while recording && [ "$i" -lt 50 ]; do
		sleep 0.1
		i=$((i + 1))
	done

	out=$(cat "$path_file" 2>/dev/null)
	rm -f "$pid_file" "$path_file"

	# :: Path on the clipboard rather than the video itself -- wl-copy would have
	# :: to hold the whole file in memory, and every paste target here wants a
	# :: path anyway.
	[ -n "$out" ] && printf '%s' "$out" | wl-copy
	notify-send -t 3000 "Recording" "Saved ${out##*/} — path copied"
}

case "${1:-toggle}" in
toggle)
	if recording; then stop; else start region "$2"; fi
	;;
region | output)
	start "$1" "$2"
	;;
stop)
	stop
	;;
status)
	if recording; then echo 1; else echo 0; fi
	;;
*)
	echo "usage: wf-record.sh [toggle|region|output|stop|status] [audio]" >&2
	exit 1
	;;
esac
