#!/usr/bin/python3

# :: Hyprland socket2 listener — closes the clamshell gap.
# ::
# :: lid-close.sh only ever runs on the lid-switch event, so unplugging the
# :: external display while the lid is ALREADY closed leaves the machine awake,
# :: unlocked and blind (eDP-1 disabled, no external output at all) until
# :: Noctalia's idle timers catch it — hyprlock at 660s, suspend at 1800s.
# ::
# :: This watches for `monitorremoved` and, when the lid is closed, hands the
# :: decision straight back to lid-close.sh, so the clamshell rule itself lives
# :: in exactly one place.
# ::
# :: Stdlib only, and pinned to /usr/bin/python3 on purpose: `python3` in PATH
# :: is an asdf shim pointing at a user-managed interpreter that moves on a
# :: version switch, and a session-critical listener must not depend on that.
# ::
# :: Started from hyprland.lua autostart (`monitor-watch.py`).

import os
import socket
import subprocess
import sys
import time
from pathlib import Path

# :: lid-close.sh sits next to this file; resolve() so it works via the
# :: ~/.config/hypr symlink too.
LID_CLOSE = Path(__file__).resolve().parent / "lid-close.sh"

# :: This box reports the lid as .../LID/state (not LID0) — glob so a kernel or
# :: hardware rename doesn't silently break the gate.
LID_DIR = Path("/proc/acpi/button/lid")

# :: Give Hyprland a beat to drop the output from `hyprctl monitors` before
# :: lid-close.sh queries it, otherwise it can still see the monitor we just lost.
SETTLE = 0.5


# :: Shared with lid-close.sh. Hyprland hands autostarted children stderr on
# :: /dev/null, so printing is invisible — this has to be a real file or the
# :: whole path is undebuggable after the fact.
LOG_FILE = Path(
    os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache"
) / "hypr" / "clamshell.log"


def log(msg):
    stamp = time.strftime("%Y-%m-%d %H:%M:%S")
    try:
        LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
        with LOG_FILE.open("a") as fh:
            fh.write(f"{stamp} monitor-watch: {msg}\n")
    except OSError:
        pass
    print(f"[monitor-watch] {msg}", file=sys.stderr, flush=True)


def socket2_path():
    runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    base = Path(runtime) / "hypr"
    his = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if his:
        return base / his / ".socket2.sock"

    # :: Fallback for a manual launch outside the session env: newest instance.
    instances = sorted(
        (d for d in base.glob("*") if d.is_dir()),
        key=lambda d: d.stat().st_mtime,
        reverse=True,
    )
    return instances[0] / ".socket2.sock" if instances else None


def lid_closed():
    for state in LID_DIR.glob("*/state"):
        try:
            return "closed" in state.read_text()
        except OSError:
            continue
    # :: No lid sensor at all -> desktop; never suspend on a monitor unplug.
    return False


def connect(retries=30, delay=1.0):
    # :: Autostart can beat the socket into existence, so retry rather than die.
    for _ in range(retries):
        path = socket2_path()
        if path and path.exists():
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            try:
                sock.connect(str(path))
                return sock
            except OSError:
                sock.close()
        time.sleep(delay)
    return None


def handle_removed(name):
    if not lid_closed():
        log(f"{name} removed, lid open -> nothing to do")
        return

    time.sleep(SETTLE)

    # :: lid-close.sh re-checks for a surviving external output, so unplugging
    # :: one of two externals is a no-op here. It blocks in `systemctl suspend`
    # :: until resume, which conveniently parks this loop for the duration.
    log(f"{name} removed, lid closed -> re-running lid-close.sh")
    subprocess.run([str(LID_CLOSE)], check=False)


def main():
    sock = connect()
    if sock is None:
        log("could not reach socket2; exiting")
        return 1

    log("listening on socket2")
    buf = b""
    with sock:
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                log("socket2 closed; exiting")
                return 0

            # :: socket2 is newline-delimited `event>>data`; keep the partial tail.
            buf += chunk
            *lines, buf = buf.split(b"\n")
            for line in lines:
                event = line.decode("utf-8", "replace")
                if event.startswith("monitorremoved>>"):
                    handle_removed(event.split(">>", 1)[1])


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
