--!nonstrict
-- Bar widget: reflects whether ../../sway/scripts/wf-record.sh is recording.
--
-- The script is the single source of truth. It writes the recorder's pid to
-- $XDG_RUNTIME_DIR/wf-record.pid and the output path to wf-record.path, so this
-- widget stays correct no matter how the recording was started -- keybind,
-- terminal, or this widget -- and needs no state shared with the script beyond
-- those two files.
--
-- Liveness is /proc/<pid>, not `kill -0`: it is a plain stat on the bar's tick
-- rather than a subprocess spawn every second.

local RUN_DIR = noctalia.getenv("XDG_RUNTIME_DIR") or "/tmp"
local PID_FILE = `{RUN_DIR}/wf-record.pid`
local PATH_FILE = `{RUN_DIR}/wf-record.path`
local SCRIPT = "~/.config/sway/scripts/wf-record.sh"

-- :: Idle ticks only need to notice a recording that started elsewhere, so they
-- :: run slower than the once-a-second the elapsed counter needs.
local TICK_RECORDING = 1000
local TICK_IDLE = 2000

local hideWhenIdle = noctalia.getConfig("hide_when_idle")
local showElapsed = noctalia.getConfig("show_elapsed")

-- Returns the live recorder pid, or nil when nothing is recording.
local function livePid()
	local contents = noctalia.readFile(PID_FILE)
	if not contents then
		return nil
	end
	local pid = tonumber(noctalia.string.trim(contents))
	if not pid then
		return nil
	end
	-- :: A pidfile can outlive its process (SIGKILL, a crash, a reboot that left
	-- :: /tmp behind), so the file existing is not enough -- check the process.
	if not noctalia.fileExists(`/proc/{pid}`) then
		return nil
	end
	return pid
end

local function elapsedSeconds()
	-- :: The script writes the pidfile once, at launch, so its mtime IS the
	-- :: recording's start time. That means the counter survives a shell reload
	-- :: mid-recording, which a variable set in this script would not.
	local info = noctalia.fileInfo(PID_FILE)
	if not info then
		return 0
	end
	return math.max(0, os.time() - info.mtime)
end

local function formatDuration(seconds)
	local minutes = seconds // 60
	local secs = seconds % 60
	if minutes < 60 then
		return string.format("%d:%02d", minutes, secs)
	end
	return string.format("%d:%02d:%02d", minutes // 60, minutes % 60, secs)
end

local function currentFileName()
	local path = noctalia.readFile(PATH_FILE)
	if not path then
		return nil
	end
	path = noctalia.string.trim(path)
	return path:match("([^/]+)$")
end

local function showRecording()
	noctalia.setUpdateInterval(TICK_RECORDING)

	barWidget.setGlyph("video")
	barWidget.setGlyphColor("error")
	barWidget.setColor("error")
	barWidget.setText(if showElapsed then formatDuration(elapsedSeconds()) else "")

	local rows = { { key = noctalia.tr("tooltip.recording"), value = formatDuration(elapsedSeconds()) } }
	local name = currentFileName()
	if name then
		table.insert(rows, { key = noctalia.tr("tooltip.file"), value = name })
	end
	table.insert(rows, { key = "", value = noctalia.tr("tooltip.hint") })
	barWidget.setTooltip(rows)

	barWidget.setVisible(true)
end

local function showIdle()
	noctalia.setUpdateInterval(TICK_IDLE)

	barWidget.setGlyph("video-off")
	barWidget.setGlyphColor("on_surface_variant")
	barWidget.setColor("on_surface_variant")
	barWidget.setText("")
	barWidget.setTooltip({
		{ key = noctalia.tr("tooltip.idle"), value = "" },
		{ key = "", value = noctalia.tr("tooltip.hint-idle") },
	})

	-- :: Kept ticking while hidden -- this is a poller, and it has to notice a
	-- :: recording started from the keybind in order to show itself again.
	barWidget.setVisible(not hideWhenIdle)
end

function update()
	if livePid() then
		showRecording()
	else
		showIdle()
	end
end

-- :: `toggle` rather than `stop`, so the widget is symmetric with the keybind:
-- :: it stops a running recording, and from idle it runs slurp to start one.
function onClick()
	noctalia.runAsync(`{SCRIPT} toggle`)
end
