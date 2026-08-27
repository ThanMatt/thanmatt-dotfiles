# Recording Indicator

Bar widget that mirrors `sway/scripts/wf-record.sh`. Shows a red video glyph and
the elapsed time while a recording is running, and hides itself when idle.
Clicking it is the same as `$mod+shift+r`: it stops a running recording, or
starts a new region capture from idle.

It does not record anything itself — it reads the pidfile the script writes to
`$XDG_RUNTIME_DIR/wf-record.pid`, so it is correct no matter how the recording
was started.

## Setup on a new machine

The plugin lives in this repo, so it has to be registered as a local source
once. Both commands are idempotent:

    noctalia msg plugins source add local path ~/.config/noctalia/plugins
    noctalia msg plugins enable thanmatt/wf-record

## Placement gotcha

`../../config.toml` alone is NOT enough to put the widget on the bar.
Noctalia layers `~/.local/state/noctalia/settings.toml` (written by the Settings
UI) *over* the config in this repo, and that file carries its own copy of
`bar.default.end`. If the widget does not appear, the state file is shadowing
it: add `"recording"` to the `end` array there too, or drag the widget in via
Settings → Bar, which rewrites the same file.

## Why not the official plugin

`noctalia/screen_recorder` covers this ground and is maintained upstream, but it
captures a whole monitor or a portal selection only — `recorder_service.luau`
declares `VIDEO_SOURCES = { focused = true, portal = true }` — and the point of
this setup is the `slurp` region crop.
