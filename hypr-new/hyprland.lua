-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- HYPRLAND CONFIG (ported from ../sway/config)          --
-- :: Keybindings + equivalents mirrored from the Sway    --
-- :: setup. Where Sway has no 1:1 in Hyprland, the        --
-- :: closest idiom is used and noted with a `-- ::` note. --
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

-- Refer to the wiki for more information.
-- https://wiki.hypr.land/Configuring/Start/

------------------
---- MONITORS ----
------------------

-- :: Sway output layout:
-- ::   DP-1 / DP-2  2560x1440@120  at 0,0   (only one external is used at a time)
-- ::   eDP-1        1920x1080      at 2560,180
-- :: adaptive_sync (VRR): Sway had `output * adaptive_sync on`, but these panels
-- :: report no hardware VRR (vrr_capable=0 in the Hyprland log), so forcing it
-- :: only logs "No Adaptive sync support" errors. Left off; add `vrr = 1` to a
-- :: specific output only if you attach a VRR-capable display.
hl.monitor({ output = "DP-1", mode = "2560x1440@120", position = "0x0", scale = 1 })
hl.monitor({ output = "DP-2", mode = "2560x1440@120", position = "0x0", scale = 1 })
hl.monitor({ output = "eDP-1", mode = "1920x1080", position = "2560x180", scale = 1 })

-- :: Fallback for any other/unknown output (auto-enable, like Sway's `output * enable`)
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

---------------------
---- MY PROGRAMS ----
---------------------

local terminal = "kitty"

-------------------
---- AUTOSTART ----
-------------------

-- :: Mirrors the Sway `exec` lines. Noctalia (quickshell) owns bar / launcher /
-- :: notifications / idle / wallpaper / night-light / OSD, same as the Sway setup.
hl.on("hyprland.start", function()
	-- :: xdg-desktop-portal(s). Nothing else on this system starts these — no
	-- :: session manager (uwsm) is in use, and graphical-session.target refuses
	-- :: manual activation here, so the portals never come up on their own.
	-- :: Without them, apps that ask the FreeDesktop Settings portal for
	-- :: prefers-color-scheme (Firefox, 1Password/Electron) never learn dark
	-- :: mode is on, even though gsettings itself is already correct. Import
	-- :: env into the D-Bus activation environment first, then start the
	-- :: Hyprland-specific backend plus the GTK backend (hyprland-portals.conf
	-- :: routes unhandled interfaces, including Settings, to gtk) and the
	-- :: main router.
	hl.exec_cmd(
		"dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE"
	)
	hl.exec_cmd("/usr/libexec/xdg-desktop-portal-hyprland")
	hl.exec_cmd("/usr/libexec/xdg-desktop-portal-gtk")
	hl.exec_cmd("/usr/libexec/xdg-desktop-portal")

	-- :: Noctalia shell. Tries v4 (quickshell) first; NOCTALIA_SETTINGS_FILE
	-- :: points at a Hyprland-only settings.json (hyprlock lock wiring) so
	-- :: Sway keeps Noctalia's built-in lock from the default settings.json.
	-- :: Only settings.json differs — the config dir (themes/plugins/colors)
	-- :: stays shared. $HOME expands via sh.
	-- :: Falls back to the native v5 binary (~/.config/noctalia/config.toml)
	-- :: if `qs -c noctalia-shell` fails to start — e.g. quickshell isn't
	-- :: installed, or the noctalia-shell QML config is gone. v5 doesn't use
	-- :: qs/QML at all, so this is what picks it up once v4 is retired.
	hl.exec_cmd(
		"env NOCTALIA_SETTINGS_FILE=$HOME/.config/noctalia/settings.hyprland.json qs -c noctalia-shell "
			.. "|| noctalia -d"
	)
	hl.exec_cmd("hypridle") -- :: sleep/lock broker for hyprlock (see hypridle.conf)
	hl.exec_cmd("~/.config/hypr/scripts/monitor-watch.py") -- :: monitorremoved -> re-run the clamshell check (see LID SWITCH)
	hl.exec_cmd("~/.config/sway/scripts/audio-routing.sh") -- :: PipeWire routing (WM-agnostic)
	hl.exec_cmd("systemctl --user start app-org.kde.kdeconnect.daemon@autostart.service")
	hl.exec_cmd("kdeconnect-indicator")
end)

-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- :: Session PATH is whatever started Hyprland (systemd --user shows just
-- :: /usr/local/bin:/usr/bin) — it never picks up ~/.cargo/bin or ~/.local/bin
-- :: the way an interactive fish shell does. Noctalia widgets run their
-- :: commands through /bin/sh, which inherits this session PATH, not fish's,
-- :: so cargo-installed CLIs (e.g. ai-usagebar) come back "command not found"
-- :: even though they're on disk. Prepend both here for every child process.
-- :: Built with os.getenv (not a literal "$HOME/...:$PATH" string) because
-- :: hl.env does not shell-expand its value -- a literal "$PATH" would set
-- :: PATH to that unexpanded text and break every PATH lookup for anything
-- :: Hyprland spawns afterward (confirmed: broke noctalia/hypridle autostart
-- :: entirely on the first attempt).
local home = os.getenv("HOME")
hl.env("PATH", home .. "/.cargo/bin:" .. home .. "/.local/bin:" .. os.getenv("PATH"))

-- :: Same problem, different variable: modules/gitlab.el reads these via
-- :: getenv at Emacs startup, but Emacs is spawned by Hyprland/the launcher,
-- :: not an interactive fish shell -- `set -Ux` in fish never reaches it.
hl.env("GITLAB_PROJECT_ID", "53733314")
hl.env("GITLAB_PROJECT_NAME", "mos")

-----------------------
---- LOOK AND FEEL ----
-----------------------

hl.config({
	general = {
		-- :: Sway: `gaps inner 8px`, `gaps outer 2px`
		gaps_in = 8,
		gaps_out = 2,

		-- :: Sway: `default_border pixel 2`
		border_size = 2,

		-- :: Gruvbox borders, from Sway's client.focused / client.unfocused childBorder
		col = {
			active_border = "rgb(7daea3)",
			inactive_border = "rgb(282828)",
		},

		resize_on_border = false,
		allow_tearing = false,
		layout = "dwindle",
	},

	decoration = {
		rounding = 10,
		rounding_power = 2,

		active_opacity = 1.0,
		inactive_opacity = 1.0,

		shadow = {
			enabled = true,
			range = 4,
			render_power = 3,
			color = 0xee1a1a1a,
		},

		blur = {
			enabled = true,
			size = 3,
			passes = 1,
			vibrancy = 0.1696,
		},
	},

	animations = {
		enabled = true,
	},
})

-- Curves + animations, see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
-- ::
-- :: ANIMATION SPEED KNOB. Hyprland `speed` is a DURATION in centiseconds
-- :: (100ms units): HIGHER = SLOWER, LOWER = FASTER. `animSpeed` below scales
-- :: every bezier leaf at once — drop it for snappier, raise it for lazier.
-- ::   1.0 = Hyprland defaults   0.6 ≈ 40% faster   0.4 = very snappy
-- :: (Spring leaves — window open/close/move — ignore `speed`; their pace comes
-- ::  from the `easy` spring's stiffness/dampening, tuned snappier just below.)
local animSpeed = 1.0

hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.curve("almostLinear", { type = "bezier", points = { { 0.5, 0.5 }, { 0.75, 1 } } })
hl.curve("quick", { type = "bezier", points = { { 0.15, 0 }, { 0.1, 1 } } })

-- :: Snappier window spring (was stiffness 71.26 / dampening 15.83).
-- :: Higher stiffness = faster; raise dampening with it to avoid overshoot.
hl.curve("easy", { type = "spring", mass = 1, stiffness = 125, dampening = 18 })

-- :: Helper: applies enabled + the global speed scale so every leaf reads clean.
local function anim(leaf, speed, opts)
	opts = opts or {}
	opts.leaf = leaf
	opts.enabled = true
	opts.speed = speed * animSpeed
	hl.animation(opts)
end

anim("global", 10, { bezier = "default" })
anim("border", 5.39, { bezier = "easeOutQuint" })
anim("windows", 4.79, { spring = "easy" })
anim("windowsIn", 4.1, { spring = "easy", style = "popin 87%" })
anim("windowsOut", 1.49, { bezier = "linear", style = "popin 87%" })
anim("fadeIn", 1.73, { bezier = "almostLinear" })
anim("fadeOut", 1.46, { bezier = "almostLinear" })
anim("fade", 3.03, { bezier = "quick" })
anim("layers", 3.81, { bezier = "easeOutQuint" })
anim("layersIn", 4, { bezier = "easeOutQuint", style = "fade" })
anim("layersOut", 1.5, { bezier = "linear", style = "fade" })
anim("fadeLayersIn", 1.79, { bezier = "almostLinear" })
anim("fadeLayersOut", 1.39, { bezier = "almostLinear" })
-- :: Horizontal push (Sway/i3 feel) instead of a cross-fade. In/Out share one
-- :: speed on purpose — with `slide` a mismatched pair makes the outgoing and
-- :: incoming workspace visibly desync mid-transition.
anim("workspaces", 2.4, { bezier = "easeOutQuint", style = "slide" })
anim("workspacesIn", 2.4, { bezier = "easeOutQuint", style = "slide" })
anim("workspacesOut", 2.4, { bezier = "easeOutQuint", style = "slide" })
-- :: Scratchpad (special:magic, SUPER+ALT+minus). Without these three the leaves
-- :: inherit `workspaces` above, i.e. the plain horizontal slide. `slidevert`
-- :: drops in from the top instead, so the scratchpad reads as an overlay
-- :: rather than a workspace switch. (`slidefadevert` = same + a cross-fade.)
-- :: In/Out share a speed for the same desync reason as the workspace leaves.
anim("specialWorkspace", 1.6, { bezier = "easeOutQuint", style = "slidevert" })
anim("specialWorkspaceIn", 1.6, { bezier = "easeOutQuint", style = "slidevert" })
anim("specialWorkspaceOut", 1.6, { bezier = "easeOutQuint", style = "slidevert" })
anim("zoomFactor", 7, { bezier = "quick" })

hl.config({
	dwindle = {
		preserve_split = true,
	},
})

-- :: Window GROUPS (Hyprland's tabbed-window equivalent). See KEYBINDINGS below
-- :: for how to build one. The groupbar draws the tabs so a group is visible.
hl.config({
	group = {
		auto_group = true, -- :: a new window opened while a group is focused joins it
		drag_into_group = true, -- :: hold SUPER and mouse-drag a window onto a group to merge it
		col = {
			border_active = "rgb(7daea3)", -- :: gruvbox aqua (matches window borders)
			border_inactive = "rgb(282828)",
		},
		groupbar = {
			enabled = true,
			height = 18,
			font_size = 11,
			gradients = false,
			col = {
				active = "rgb(7daea3)",
				inactive = "rgb(282828)",
			},
		},
	},
})

---------------
---- INPUT ----
---------------

-- :: Ported from Sway `input type:{keyboard,pointer,touchpad}` blocks.
hl.config({
	input = {
		kb_layout = "us",

		follow_mouse = 1,

		-- :: Sway pointer: `accel_profile flat`, `pointer_accel -0.5`, `natural_scroll enabled`
		accel_profile = "flat",
		sensitivity = -0.5, -- :: pointer_accel -0.5
		natural_scroll = true, -- :: mouse natural scroll

		-- :: Sway keyboard: repeat_delay 300, repeat_rate 50
		repeat_delay = 300,
		repeat_rate = 50,

		-- :: Sway touchpad: dwt / tap / natural_scroll enabled
		touchpad = {
			disable_while_typing = true,
			tap_to_click = true,
			natural_scroll = true,
		},
	},
})

-- :: Trackpad speed. `input.touchpad` has NO sensitivity option — touchpad speed
-- :: comes from `input.sensitivity` / `input.accel_profile`, which above are set
-- :: for the mouse (flat, -0.5) and would otherwise make the trackpad crawl.
-- :: So override just the trackpad per-device (name from `hyprctl devices`).
-- :: sensitivity range is -1.0 .. 1.0; adaptive re-enables pointer acceleration,
-- :: which feels much better than `flat` on a touchpad. Tune 0.2 -> 0.6 to taste.
hl.device({
	name = "synaptics-tm3381-002",
	accel_profile = "adaptive",
	sensitivity = 0.3,
})

-- :: Sway had a 3-finger equivalent via touchpad scrolling; keep Hyprland's
-- :: 3-finger horizontal swipe to switch workspaces.
hl.gesture({
	fingers = 3,
	direction = "horizontal",
	action = "workspace",
})

-- :: Sway `input "type:touch" { events disabled }` has no global Hyprland toggle;
-- :: disable per touch device instead if needed, e.g.:
-- hl.device({ name = "your-touchscreen-name", enabled = false })

---------------------
---- KEYBINDINGS ----
---------------------

local mainMod = "SUPER" -- :: Sway `$mod Mod4`

-- :: Home-row (vim) direction keys, matching Sway's $left/$down/$up/$right
local L, D, U, R = "H", "J", "K", "L"

--------------------------------------------------------------------------------
-- Basics
--------------------------------------------------------------------------------
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal)) -- :: $mod+Return -> terminal
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal)) -- :: $mod+t -> kitty
hl.bind(mainMod .. " + Q", hl.dsp.window.close()) -- :: $mod+q -> kill
hl.bind(mainMod .. " + SHIFT + C", hl.dsp.exec_cmd("hyprctl reload")) -- :: $mod+Shift+c -> reload
hl.bind(mainMod .. " + SHIFT + E", hl.dsp.exit()) -- :: $mod+Shift+e -> exit session

hl.bind(mainMod .. "+ G", hl.dsp.exec_cmd("noctalia msg panel-toggle alexander/mimir:chat"))

-- :: Launcher / menus / clipboard / emoji / session — all Noctalia IPC (as in Sway).
-- :: Same v4-first, v5-fallback pattern as the AUTOSTART block: v4's `qs ipc call`
-- :: syntax is tried first, falling back to v5's `noctalia msg` if `qs` isn't
-- :: present (confirmed against the running v5 daemon: panel-toggle launcher,
-- :: with /emo and /clip context strings, and panel-toggle session).
hl.bind(
	mainMod .. " + Space",
	hl.dsp.exec_cmd("qs -c noctalia-shell ipc call launcher toggle || noctalia msg panel-toggle launcher")
) -- :: $mod+space
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd("~/.config/sway/scripts/calc.sh")) -- :: $mod+c -> calculator
hl.bind(
	mainMod .. " + Period",
	hl.dsp.exec_cmd("qs -c noctalia-shell ipc call launcher emoji || noctalia msg panel-toggle launcher /emo")
) -- :: $mod+period
hl.bind(
	mainMod .. " + ALT + V",
	hl.dsp.exec_cmd("qs -c noctalia-shell ipc call launcher clipboard || noctalia msg panel-toggle clipboard")
) -- :: $mod+alt+v
hl.bind(
	mainMod .. " + ALT + Space",
	hl.dsp.exec_cmd("qs -c noctalia-shell ipc call sessionMenu toggle || noctalia msg panel-toggle session")
) -- :: $mod+alt+space
-- :: Manual lock -> hyprlock (Super+L is taken by focus-right). Direct call so
-- :: it works even if hypridle isn't running; `pidof` guard avoids a 2nd instance.
hl.bind(mainMod .. " + ALT + L", hl.dsp.exec_cmd("pidof hyprlock || hyprlock")) -- :: $mod+alt+l -> lock
-- :: Chill mode toggle -- see ChillModeRule (WINDOWS AND WORKSPACES, below) for
-- :: what this actually does. Wrapped in a closure (not passed directly) so
-- :: definition order in this file doesn't matter -- the global lookup happens
-- :: at keypress time, not here.
hl.bind(mainMod .. " + ALT + F", function()
	ChillModeToggle()
end) -- :: $mod+alt+f -> toggle chill mode

--------------------------------------------------------------------------------
-- Screenshots (grim / slurp / swappy) — identical tooling to Sway
--------------------------------------------------------------------------------
hl.bind("Print", hl.dsp.exec_cmd([[grim -g "$(slurp)" - | wl-copy]])) -- :: region -> clipboard
hl.bind("CTRL + Print", hl.dsp.exec_cmd([[grim - | wl-copy]])) -- :: fullscreen -> clipboard
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd([[grim -g "$(slurp)" - | swappy -f -]])) -- :: region -> annotate
-- :: Current-window shot: Sway used swaymsg get_tree; Hyprland uses hyprctl activewindow.
hl.bind(
	mainMod .. " + SHIFT + Print",
	hl.dsp.exec_cmd(
		[[grim -g "$(hyprctl -j activewindow | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')" ~/Pictures/Screenshots/$(date +'%Y-%m-%d-%H%M%S_grim.png')]]
	)
)

--------------------------------------------------------------------------------
-- Focus (vim keys + arrows)  — Sway `focus left/down/up/right`
--------------------------------------------------------------------------------
hl.bind(mainMod .. " + " .. L, hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + " .. D, hl.dsp.focus({ direction = "down" }))
hl.bind(mainMod .. " + " .. U, hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + " .. R, hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + down", hl.dsp.focus({ direction = "down" }))
hl.bind(mainMod .. " + up", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))

--------------------------------------------------------------------------------
-- Move window (vim keys + arrows)  — Sway `move left/down/up/right 30px/10px`
-- :: Sway's `move <dir> <px>` did double duty: reorder in the tree when tiled,
-- :: nudge by pixels when floating. Hyprland splits those across two
-- :: dispatchers — `window.move{direction=}` (movewindow) only ever SNAPS a
-- :: floating window to the monitor edge, and `window.move{x=,y=,relative=}`
-- :: (moveactive) only does anything useful when floating. So dispatch on the
-- :: window's state, restoring the Sway feel: free-form px nudging while
-- :: floating, layout reordering while tiled.
-- :: NOTE: bind takes a Lua function as well as a dispatcher, so this runs
-- :: in-process — no script spawn per keypress, which matters with
-- :: `repeating = true` at a 50/s repeat rate.
--------------------------------------------------------------------------------
local moveStep = 30 -- :: h/j/k/l   (Sway `move <dir> 30px`)
local moveFine = 10 -- :: arrow keys (Sway `move <dir> 10px`)

local function moveDwim(dir, px)
	return function()
		local w = hl.get_active_window()
		if w and w.floating then
			local dx, dy = 0, 0
			if dir == "left" then
				dx = -px
			elseif dir == "right" then
				dx = px
			elseif dir == "up" then
				dy = -px
			else
				dy = px
			end
			hl.dispatch(hl.dsp.window.move({ x = dx, y = dy, relative = true }))
		else
			hl.dispatch(hl.dsp.window.move({ direction = dir }))
		end
	end
end

local moveOpts = { repeating = true } -- :: hold the key to keep nudging

hl.bind(mainMod .. " + SHIFT + " .. L, moveDwim("left", moveStep), moveOpts)
hl.bind(mainMod .. " + SHIFT + " .. D, moveDwim("down", moveStep), moveOpts)
hl.bind(mainMod .. " + SHIFT + " .. U, moveDwim("up", moveStep), moveOpts)
hl.bind(mainMod .. " + SHIFT + " .. R, moveDwim("right", moveStep), moveOpts)
hl.bind(mainMod .. " + SHIFT + left", moveDwim("left", moveFine), moveOpts)
hl.bind(mainMod .. " + SHIFT + down", moveDwim("down", moveFine), moveOpts)
hl.bind(mainMod .. " + SHIFT + up", moveDwim("up", moveFine), moveOpts)
hl.bind(mainMod .. " + SHIFT + right", moveDwim("right", moveFine), moveOpts)

-- :: Center a floating window when it gets lost (moveactive is unclamped — a
-- :: nudge can push a window mostly off-screen).
hl.bind(mainMod .. " + SHIFT + G", hl.dsp.window.center())

--------------------------------------------------------------------------------
-- Workspaces  — Sway `workspace number N` / `move container to workspace number N`
--------------------------------------------------------------------------------
for i = 1, 10 do
	local key = i % 10 -- :: 10 maps to key 0, matching Sway
	hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
	hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- :: Sway `Ctrl+$mod+l/h -> workspace next/prev_on_output`
hl.bind("CTRL + " .. mainMod .. " + " .. R, hl.dsp.focus({ workspace = "m+1" })) -- :: next on this monitor
hl.bind("CTRL + " .. mainMod .. " + " .. L, hl.dsp.focus({ workspace = "m-1" })) -- :: prev on this monitor

--------------------------------------------------------------------------------
-- Layout  — Sway split / layout binds
--------------------------------------------------------------------------------
hl.bind(mainMod .. " + backslash", hl.dsp.layout("togglesplit")) -- :: $mod+backslash split toggle (dwindle)
hl.bind(mainMod .. " + E", hl.dsp.layout("togglesplit")) -- :: $mod+e layout toggle split

-- :: Hyprland dwindle has no explicit horizontal/vertical split like Sway's
-- :: `split h` / `split v`; the next split follows window aspect ratio and
-- :: togglesplit flips it. Kept mapped to togglesplit for muscle memory.
hl.bind(mainMod .. " + bar", hl.dsp.layout("togglesplit")) -- :: $mod+bar   split h
hl.bind(mainMod .. " + minus", hl.dsp.layout("togglesplit")) -- :: $mod+minus split v

-- :: Sway tabbed/stacking -> Hyprland groups (tabbed-style). No stacking mode,
-- :: so $mod+s cycles group members instead of stacking.
-- :: Sway tabbed/stacking -> Hyprland GROUPS (tabbed windows). Workflow:
-- ::   1. SUPER+W on a window          -> turns it into a (1-tab) group
-- ::   2. open more windows            -> they auto-join the focused group (auto_group)
-- ::      or SUPER+drag a window onto the group with the mouse (drag_into_group)
-- ::   3. SUPER+S                       -> cycle between tabs in the group
-- ::   4. SUPER+W again                 -> dissolve the group
-- :: NOTE: Hyprland 0.56's Lua API has no `moveintogroup`/`movewindoworgroup`
-- :: wrapper, so there is no keybind to pull an EXISTING window in — use the
-- :: mouse-drag (step 2) for that. group.next below is cycle-only (no stacking).
hl.bind(mainMod .. " + W", hl.dsp.group.toggle()) -- :: $mod+w -> create/dissolve group
hl.bind(mainMod .. " + S", hl.dsp.group.next()) -- :: $mod+s -> cycle to next tab in group

hl.bind(mainMod .. " + M", hl.dsp.window.fullscreen()) -- :: $mod+m fullscreen toggle
hl.bind(mainMod .. " + SHIFT + Space", hl.dsp.window.float({ action = "toggle" })) -- :: $mod+Shift+space floating toggle

-- :: Reaching floating windows from the keyboard. The directional focus binds
-- :: above (movefocus) do NOT cross the float/tile boundary — from a tiled
-- :: window they skip floating windows entirely (and can jump to the next
-- :: monitor instead); from a floating window they do nothing. `cyclenext` is
-- :: the only dispatcher that crosses over, so:
-- ::   SUPER+Tab -> cycle every window on the workspace, floating included
-- ::   SUPER+G   -> Sway's `focus mode_toggle`: hop tiled <-> floating layer
hl.bind(mainMod .. " + Tab", hl.dsp.window.cycle_next())
hl.bind(mainMod .. " + G", hl.dsp.exec_cmd("~/.config/hypr/scripts/focus-mode-toggle.sh"))

-- :: RAISE-ON-FOCUS for floating windows. Hyprland has no config option for this
-- :: (checked `hyprctl descriptions`); focus and stacking order are independent, so
-- :: a floating window focused by hover (follow_mouse = 1), SUPER+Tab (cyclenext) or
-- :: SUPER+G stays buried under whatever floats above it. Hook the focus event and
-- :: push the new active window to the top of the z-stack instead.
-- :: Guarded on `floating` — tiled windows never overlap, so re-stacking them is
-- :: pointless, and it would fight fullscreen/pinned windows sitting above them.
-- :: alterzorder does not move focus, so this can't re-trigger itself.
hl.on("window.active", function()
	local w = hl.get_active_window()
	if w and w.floating then
		hl.dispatch(hl.dsp.window.bring_to_top())
	end
end)

-- :: Sway `$mod+a focus parent` relies on i3/Sway's container tree, which
-- :: Hyprland's dwindle layout does not expose — no direct equivalent.
-- hl.bind(mainMod .. " + A", ...)

--------------------------------------------------------------------------------
-- Scratchpad  — Sway used swaymsg scripts (not portable). Hyprland's idiomatic
-- :: equivalent is a special workspace ("magic").
--------------------------------------------------------------------------------
hl.bind(mainMod .. " + SHIFT + minus", hl.dsp.window.move({ workspace = "special:magic" })) -- :: send to scratchpad
hl.bind(mainMod .. " + ALT + minus", hl.dsp.workspace.toggle_special("magic")) -- :: toggle scratchpad

--------------------------------------------------------------------------------
-- Resize submap  — Sway `mode "resize"`
--------------------------------------------------------------------------------
-- :: RESIZE STEP KNOB (px per keypress). Deltas map to Hyprland's resizeactive.
-- :: `step` = h/j/k/l (coarse), `fine` = arrow keys. Bump these to resize faster.
local step = 60 -- :: was 30
local fine = 20 -- :: was 10
hl.define_submap("resize", function()
	hl.bind(L, hl.dsp.window.resize({ x = -step, y = 0, relative = true })) -- :: shrink width
	hl.bind(R, hl.dsp.window.resize({ x = step, y = 0, relative = true })) -- :: grow width
	hl.bind(U, hl.dsp.window.resize({ x = 0, y = -step, relative = true })) -- :: shrink height
	hl.bind(D, hl.dsp.window.resize({ x = 0, y = step, relative = true })) -- :: grow height

	hl.bind("left", hl.dsp.window.resize({ x = -fine, y = 0, relative = true }))
	hl.bind("right", hl.dsp.window.resize({ x = fine, y = 0, relative = true }))
	hl.bind("up", hl.dsp.window.resize({ x = 0, y = -fine, relative = true }))
	hl.bind("down", hl.dsp.window.resize({ x = 0, y = fine, relative = true }))

	-- :: Back to default: Enter / Escape / $mod+r
	hl.bind("Return", hl.dsp.submap("reset"))
	hl.bind("Escape", hl.dsp.submap("reset"))
	hl.bind(mainMod .. " + R", hl.dsp.submap("reset"))
end)
hl.bind(mainMod .. " + R", hl.dsp.submap("resize")) -- :: $mod+r -> enter resize mode

--------------------------------------------------------------------------------
-- Mouse  — Sway `floating_modifier $mod normal`
--------------------------------------------------------------------------------
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true }) -- :: $mod + LMB drag
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true }) -- :: $mod + RMB resize
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

--------------------------------------------------------------------------------
-- Media / brightness keys  — Sway pamixer + brightnessctl
-- :: Noctalia OSD pops automatically on PipeWire/brightness changes.
--------------------------------------------------------------------------------
-- :: `pamixer` isn't installed on this machine, so these silently no-op'd.
-- :: Noctalia already owns audio via WirePlumber, so drive volume through its
-- :: own IPC instead of adding an external dependency (confirmed against the
-- :: running daemon: 40% -> 45% for a step of 5, via `pactl get-sink-volume`).
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("noctalia msg volume-up 5"), { repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("noctalia msg volume-down 5"), { repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("noctalia msg volume-mute"))
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl set 5%+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 5%-"), { locked = true, repeating = true })

--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

-- :: Sway `for_window [app_id=...] floating enable`. In Hyprland, `class`
-- :: matches the Wayland app_id for native Wayland apps.
hl.window_rule({
	name = "float-nautilus",
	match = { class = "^(org\\.gnome\\.Nautilus)$" },
	float = true,
})
hl.window_rule({
	name = "float-qalculate",
	match = { class = "^(qalculate-gtk)$" },
	float = true,
})

-- Ignore maximize requests from all apps.
hl.window_rule({
	name = "suppress-maximize-events",
	match = { class = ".*" },
	suppress_event = "maximize",
})

-- xdg-desktop-portal-hyprland spawns hyprland-share-picker (used by OBS/any
-- app using the standard ScreenCast portal flow, unlike Discord/Vesktop which
-- build their own in-app picker) as a detached process with no workspace
-- context, so Hyprland always opens it on workspace 1 regardless of which
-- workspace is actually focused -- it looked like the picker just never
-- appeared. Pin it so it's visible immediately no matter where you are.
hl.window_rule({
	name = "pin-share-picker",
	match = { class = "^(hyprland-share-picker)$" },
	workspace = "current",
})

-- Fix some dragging issues with XWayland
hl.window_rule({
	name = "fix-xwayland-drags",
	match = {
		class = "^$",
		title = "^$",
		xwayland = true,
		float = true,
		fullscreen = false,
		pin = false,
	},
	no_focus = true,
})

--------------------------------------------------------------------------------
-- Chill mode -- float EVERY window (present + future, every workspace) so
-- Hyprland stops looking/behaving like a tiling WM; toggle back to restore
-- tiling. Classic Hyprland's `workspaceopt allfloat` dispatcher does not exist
-- in this fork (checked hl.dsp.workspace in /usr/share/hypr/stubs/hl.meta.lua:
-- only change_id/move/rename/swap_monitors/toggle_special), so this fakes it
-- with a single window_rule matching every window, flipped on/off at runtime
-- via WindowRule:set_enabled() -- the toggleable-object pattern this API uses
-- for keybinds/timers/layer rules too.
--
-- MUST be a real global (not `local`) -- both `hl.bind` above (via closure)
-- and `hyprctl eval` from outside the config (see fish/functions/chill-mode.fish)
-- need to reach ChillModeRule / ChillModeSet / ChillModeToggle by name.
ChillModeRule = hl.window_rule({
	name = "chill-mode",
	match = { class = ".*" },
	float = true,
	enabled = false,
})

-- :: State file is the single source of truth for fish's on/off message --
-- written here so it stays correct whether the toggle came from the keybind
-- or from `chill-mode` on the command line via `hyprctl eval`.
local chillModeStateFile = os.getenv("HOME") .. "/.cache/hypr/chill-mode-state"

function ChillModeSet(on)
	ChillModeRule:set_enabled(on)
	os.execute('mkdir -p "$HOME/.cache/hypr"')
	local f = io.open(chillModeStateFile, "w")
	if f then
		f:write(on and "1" or "0")
		f:close()
	end
	hl.notification.create({
		text = on and "Chill mode ON — new windows float" or "Chill mode OFF — back to tiling",
		timeout = 2500,
	})
end

function ChillModeToggle()
	ChillModeSet(not ChillModeRule:is_enabled())
end

--------------------------------
---- NOCTALIA (quickshell) -----
--------------------------------

-- :: Noctalia auto-detects the compositor (Hyprland via $HYPRLAND_INSTANCE_SIGNATURE),
-- :: so noctalia/settings.json needs no Sway->Hyprland changes. It is started from the
-- :: AUTOSTART block above (`qs -c noctalia-shell`) and owns the bar / launcher /
-- :: notifications / idle / lock / wallpaper / night-light / OSD.
-- ::
-- :: Sway just draws these layer surfaces flat; on Hyprland we can frost them.
-- :: All Noctalia surfaces share the `noctalia-*` layer namespace — blur only the
-- :: real UI panels (NOT the wallpaper/background/utility layers).
hl.layer_rule({
	name = "noctalia-blur",
	match = {
		namespace = "^(noctalia-(bar-content|launcher-overlay|notifications|osd|overview|dock|toast|desktop-widgets)-.*)$",
	},
	blur = true,
	ignore_alpha = 0.6, -- :: don't blur the transparent bar frame, only the capsules/panels
})

-- :: Dim the desktop behind the modal launcher / overview.
hl.layer_rule({
	name = "noctalia-dim-modals",
	match = { namespace = "^(noctalia-(launcher-overlay|overview)-.*)$" },
	dim_around = true,
})

-------------------------
---- LID SWITCH ---------
-------------------------

-- :: Hyprland-native port of Sway's `bindswitch lid:on/off`. `locked = true`
-- :: (== bindl) so it still fires while the screen is locked/off.
-- ::
-- :: NOTE: confirm the switch device name in a live session with
-- ::   hyprctl devices | grep -iA2 switch
-- :: and adjust "Lid Switch" below if libinput reports a different name.

-- :: These binds fire on the lid EVENT only. Unplugging the external while the
-- :: lid is already closed is a monitor event, not a lid one, so it is handled
-- :: by scripts/monitor-watch.py (autostart) — it re-runs lid-close.sh so the
-- :: clamshell rule below stays the single source of truth.

-- :: Lid CLOSE -> disable eDP-1; suspend only if no external display (clamshell).
hl.bind("switch:on:Lid Switch", hl.dsp.exec_cmd("~/.config/hypr/scripts/lid-close.sh"), { locked = true })

-- :: Lid OPEN -> re-enable the laptop panel with its configured mode/position.
-- :: (Mirrors the MONITORS block above; keep them in sync, or swap the command
-- ::  for `hyprctl reload` to re-apply every monitor rule from config.)
-- :: NOTE: `hyprctl keyword` does NOT work with the Lua config parser ("keyword
-- :: can't work with non-legacy parsers. Use eval."), so this goes through
-- :: `hyprctl eval` + hl.monitor. `disabled = false` is required — without it
-- :: the monitor keeps the disabled state lid-close.sh set.
hl.bind(
	"switch:off:Lid Switch",
	hl.dsp.exec_cmd(
		[[hyprctl eval 'hl.monitor({ output = "eDP-1", mode = "1920x1080", position = "2560x180", scale = 1, disabled = false })']]
	),
	{ locked = true }
)

-------------------------
----- NVIDIA STUFF ------
-------------------------
local function has_nvidia()
	local f = io.open("/sys/module/nvidia_drm/parameters/modeset", "r")
	if f then
		f:close()
		return true
	end
	return false
end

if has_nvidia() then
	hl.env("LIBVA_DRIVER_NAME", "nvidia")
	hl.env("GBM_BACKEND", "nvidia-drm")
	hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
end

-- safe everywhere, no condition needed
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "wayland")
