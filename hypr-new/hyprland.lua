
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
hl.monitor({ output = "DP-1",  mode = "2560x1440@120", position = "0x0",     scale = 1 })
hl.monitor({ output = "DP-2",  mode = "2560x1440@120", position = "0x0",     scale = 1 })
hl.monitor({ output = "eDP-1", mode = "1920x1080",     position = "2560x180", scale = 1 })

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
    -- :: Noctalia shell. NOCTALIA_SETTINGS_FILE points at a Hyprland-only
    -- :: settings.json (hyprlock lock wiring) so Sway keeps Noctalia's built-in
    -- :: lock from the default settings.json. Only settings.json differs — the
    -- :: config dir (themes/plugins/colors) stays shared. $HOME expands via sh.
    hl.exec_cmd("env NOCTALIA_SETTINGS_FILE=$HOME/.config/noctalia/settings.hyprland.json qs -c noctalia-shell")
    hl.exec_cmd("hypridle")                                              -- :: sleep/lock broker for hyprlock (see hypridle.conf)
    hl.exec_cmd("~/.config/sway/scripts/audio-routing.sh")              -- :: PipeWire routing (WM-agnostic)
    hl.exec_cmd("systemctl --user start app-org.kde.kdeconnect.daemon@autostart.service")
    hl.exec_cmd("kdeconnect-indicator")
end)


-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")


-----------------------
---- LOOK AND FEEL ----
-----------------------

hl.config({
    general = {
        -- :: Sway: `gaps inner 8px`, `gaps outer 2px`
        gaps_in  = 8,
        gaps_out = 2,

        -- :: Sway: `default_border pixel 2`
        border_size = 2,

        -- :: Gruvbox borders, from Sway's client.focused / client.unfocused childBorder
        col = {
            active_border   = "rgb(7daea3)",
            inactive_border = "rgb(282828)",
        },

        resize_on_border = false,
        allow_tearing    = false,
        layout           = "dwindle",
    },

    decoration = {
        rounding       = 10,
        rounding_power = 2,

        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled      = true,
            range        = 4,
            render_power = 3,
            color        = 0xee1a1a1a,
        },

        blur = {
            enabled  = true,
            size     = 3,
            passes   = 1,
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
local animSpeed = 0.6

hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1}    } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1}    } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}       } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1}    } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}     } })

-- :: Snappier window spring (was stiffness 71.26 / dampening 15.83).
-- :: Higher stiffness = faster; raise dampening with it to avoid overshoot.
hl.curve("easy",           { type = "spring", mass = 1, stiffness = 125, dampening = 18 })

-- :: Helper: applies enabled + the global speed scale so every leaf reads clean.
local function anim(leaf, speed, opts)
    opts         = opts or {}
    opts.leaf    = leaf
    opts.enabled = true
    opts.speed   = speed * animSpeed
    hl.animation(opts)
end

anim("global",        10,   { bezier = "default" })
anim("border",        5.39, { bezier = "easeOutQuint" })
anim("windows",       4.79, { spring = "easy" })
anim("windowsIn",     4.1,  { spring = "easy",         style = "popin 87%" })
anim("windowsOut",    1.49, { bezier = "linear",       style = "popin 87%" })
anim("fadeIn",        1.73, { bezier = "almostLinear" })
anim("fadeOut",       1.46, { bezier = "almostLinear" })
anim("fade",          3.03, { bezier = "quick" })
anim("layers",        3.81, { bezier = "easeOutQuint" })
anim("layersIn",      4,    { bezier = "easeOutQuint", style = "fade" })
anim("layersOut",     1.5,  { bezier = "linear",       style = "fade" })
anim("fadeLayersIn",  1.79, { bezier = "almostLinear" })
anim("fadeLayersOut", 1.39, { bezier = "almostLinear" })
anim("workspaces",    1.94, { bezier = "almostLinear", style = "fade" })
anim("workspacesIn",  1.21, { bezier = "almostLinear", style = "fade" })
anim("workspacesOut", 1.94, { bezier = "almostLinear", style = "fade" })
anim("zoomFactor",    7,    { bezier = "quick" })

hl.config({
    dwindle = {
        preserve_split = true,
    },
})

-- :: Window GROUPS (Hyprland's tabbed-window equivalent). See KEYBINDINGS below
-- :: for how to build one. The groupbar draws the tabs so a group is visible.
hl.config({
    group = {
        auto_group      = true,   -- :: a new window opened while a group is focused joins it
        drag_into_group = true,   -- :: hold SUPER and mouse-drag a window onto a group to merge it
        col = {
            border_active   = "rgb(7daea3)",   -- :: gruvbox aqua (matches window borders)
            border_inactive = "rgb(282828)",
        },
        groupbar = {
            enabled   = true,
            height    = 18,
            font_size = 11,
            gradients = false,
            col = {
                active   = "rgb(7daea3)",
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
        accel_profile  = "flat",
        sensitivity    = -0.5,   -- :: pointer_accel -0.5
        natural_scroll = true,   -- :: mouse natural scroll

        -- :: Sway keyboard: repeat_delay 300, repeat_rate 50
        repeat_delay = 300,
        repeat_rate  = 50,

        -- :: Sway touchpad: dwt / tap / natural_scroll enabled
        touchpad = {
            disable_while_typing = true,
            tap_to_click         = true,
            natural_scroll       = true,
        },
    },
})

-- :: Sway had a 3-finger equivalent via touchpad scrolling; keep Hyprland's
-- :: 3-finger horizontal swipe to switch workspaces.
hl.gesture({
    fingers   = 3,
    direction = "horizontal",
    action    = "workspace",
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
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal))               -- :: $mod+Return -> terminal
hl.bind(mainMod .. " + T",      hl.dsp.exec_cmd(terminal))               -- :: $mod+t -> kitty
hl.bind(mainMod .. " + Q",      hl.dsp.window.close())                   -- :: $mod+q -> kill
hl.bind(mainMod .. " + SHIFT + C", hl.dsp.exec_cmd("hyprctl reload"))    -- :: $mod+Shift+c -> reload
hl.bind(mainMod .. " + SHIFT + E", hl.dsp.exit())                        -- :: $mod+Shift+e -> exit session

-- :: Launcher / menus / clipboard / emoji / session — all Noctalia IPC (as in Sway)
hl.bind(mainMod .. " + Space",         hl.dsp.exec_cmd("qs -c noctalia-shell ipc call launcher toggle"))     -- :: $mod+space
hl.bind(mainMod .. " + C",             hl.dsp.exec_cmd("~/.config/sway/scripts/calc.sh"))                    -- :: $mod+c -> calculator
hl.bind(mainMod .. " + Period",        hl.dsp.exec_cmd("qs -c noctalia-shell ipc call launcher emoji"))      -- :: $mod+period
hl.bind(mainMod .. " + ALT + V",       hl.dsp.exec_cmd("qs -c noctalia-shell ipc call launcher clipboard"))  -- :: $mod+alt+v
hl.bind(mainMod .. " + ALT + Space",   hl.dsp.exec_cmd("qs -c noctalia-shell ipc call sessionMenu toggle"))  -- :: $mod+alt+space
-- :: Manual lock -> hyprlock (Super+L is taken by focus-right). Direct call so
-- :: it works even if hypridle isn't running; `pidof` guard avoids a 2nd instance.
hl.bind(mainMod .. " + ALT + L",       hl.dsp.exec_cmd("pidof hyprlock || hyprlock"))                        -- :: $mod+alt+l -> lock

--------------------------------------------------------------------------------
-- Screenshots (grim / slurp / swappy) — identical tooling to Sway
--------------------------------------------------------------------------------
hl.bind("Print",                   hl.dsp.exec_cmd([[grim -g "$(slurp)" - | wl-copy]]))          -- :: region -> clipboard
hl.bind("CTRL + Print",            hl.dsp.exec_cmd([[grim - | wl-copy]]))                        -- :: fullscreen -> clipboard
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd([[grim -g "$(slurp)" - | swappy -f -]]))      -- :: region -> annotate
-- :: Current-window shot: Sway used swaymsg get_tree; Hyprland uses hyprctl activewindow.
hl.bind(mainMod .. " + SHIFT + Print",
    hl.dsp.exec_cmd([[grim -g "$(hyprctl -j activewindow | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')" ~/Pictures/Screenshots/$(date +'%Y-%m-%d-%H%M%S_grim.png')]]))

--------------------------------------------------------------------------------
-- Focus (vim keys + arrows)  — Sway `focus left/down/up/right`
--------------------------------------------------------------------------------
hl.bind(mainMod .. " + " .. L, hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + " .. D, hl.dsp.focus({ direction = "down" }))
hl.bind(mainMod .. " + " .. U, hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + " .. R, hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))

--------------------------------------------------------------------------------
-- Move window (vim keys + arrows)  — Sway `move left/down/up/right`
-- :: Hyprland tiling moves are directional (it swaps/relocates in the layout);
-- :: the px step sizes from Sway don't apply to tiled windows.
--------------------------------------------------------------------------------
hl.bind(mainMod .. " + SHIFT + " .. L, hl.dsp.window.move({ direction = "left" }))
hl.bind(mainMod .. " + SHIFT + " .. D, hl.dsp.window.move({ direction = "down" }))
hl.bind(mainMod .. " + SHIFT + " .. U, hl.dsp.window.move({ direction = "up" }))
hl.bind(mainMod .. " + SHIFT + " .. R, hl.dsp.window.move({ direction = "right" }))
hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.window.move({ direction = "left" }))
hl.bind(mainMod .. " + SHIFT + down",  hl.dsp.window.move({ direction = "down" }))
hl.bind(mainMod .. " + SHIFT + up",    hl.dsp.window.move({ direction = "up" }))
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.move({ direction = "right" }))

--------------------------------------------------------------------------------
-- Workspaces  — Sway `workspace number N` / `move container to workspace number N`
--------------------------------------------------------------------------------
for i = 1, 10 do
    local key = i % 10 -- :: 10 maps to key 0, matching Sway
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- :: Sway `Ctrl+$mod+l/h -> workspace next/prev_on_output`
hl.bind("CTRL + " .. mainMod .. " + " .. R, hl.dsp.focus({ workspace = "m+1" }))  -- :: next on this monitor
hl.bind("CTRL + " .. mainMod .. " + " .. L, hl.dsp.focus({ workspace = "m-1" }))  -- :: prev on this monitor

--------------------------------------------------------------------------------
-- Layout  — Sway split / layout binds
--------------------------------------------------------------------------------
hl.bind(mainMod .. " + backslash", hl.dsp.layout("togglesplit"))  -- :: $mod+backslash split toggle (dwindle)
hl.bind(mainMod .. " + E",         hl.dsp.layout("togglesplit"))  -- :: $mod+e layout toggle split

-- :: Hyprland dwindle has no explicit horizontal/vertical split like Sway's
-- :: `split h` / `split v`; the next split follows window aspect ratio and
-- :: togglesplit flips it. Kept mapped to togglesplit for muscle memory.
hl.bind(mainMod .. " + bar",   hl.dsp.layout("togglesplit"))  -- :: $mod+bar   split h
hl.bind(mainMod .. " + minus", hl.dsp.layout("togglesplit"))  -- :: $mod+minus split v

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
hl.bind(mainMod .. " + W", hl.dsp.group.toggle())  -- :: $mod+w -> create/dissolve group
hl.bind(mainMod .. " + S", hl.dsp.group.next())    -- :: $mod+s -> cycle to next tab in group

hl.bind(mainMod .. " + M",             hl.dsp.window.fullscreen())            -- :: $mod+m fullscreen toggle
hl.bind(mainMod .. " + SHIFT + Space", hl.dsp.window.float({ action = "toggle" }))  -- :: $mod+Shift+space floating toggle

-- :: Sway `$mod+a focus parent` relies on i3/Sway's container tree, which
-- :: Hyprland's dwindle layout does not expose — no direct equivalent.
-- hl.bind(mainMod .. " + A", ...)

--------------------------------------------------------------------------------
-- Scratchpad  — Sway used swaymsg scripts (not portable). Hyprland's idiomatic
-- :: equivalent is a special workspace ("magic").
--------------------------------------------------------------------------------
hl.bind(mainMod .. " + SHIFT + minus", hl.dsp.window.move({ workspace = "special:magic" }))  -- :: send to scratchpad
hl.bind(mainMod .. " + ALT + minus",   hl.dsp.workspace.toggle_special("magic"))             -- :: toggle scratchpad

--------------------------------------------------------------------------------
-- Resize submap  — Sway `mode "resize"`
--------------------------------------------------------------------------------
-- :: RESIZE STEP KNOB (px per keypress). Deltas map to Hyprland's resizeactive.
-- :: `step` = h/j/k/l (coarse), `fine` = arrow keys. Bump these to resize faster.
local step = 60   -- :: was 30
local fine = 20   -- :: was 10
hl.define_submap("resize", function()
    hl.bind(L, hl.dsp.window.resize({ x = -step, y = 0,     relative = true }))  -- :: shrink width
    hl.bind(R, hl.dsp.window.resize({ x = step,  y = 0,     relative = true }))  -- :: grow width
    hl.bind(U, hl.dsp.window.resize({ x = 0,     y = -step, relative = true }))  -- :: shrink height
    hl.bind(D, hl.dsp.window.resize({ x = 0,     y = step,  relative = true }))  -- :: grow height

    hl.bind("left",  hl.dsp.window.resize({ x = -fine, y = 0,     relative = true }))
    hl.bind("right", hl.dsp.window.resize({ x = fine,  y = 0,     relative = true }))
    hl.bind("up",    hl.dsp.window.resize({ x = 0,     y = -fine, relative = true }))
    hl.bind("down",  hl.dsp.window.resize({ x = 0,     y = fine,  relative = true }))

    -- :: Back to default: Enter / Escape / $mod+r
    hl.bind("Return",           hl.dsp.submap("reset"))
    hl.bind("Escape",           hl.dsp.submap("reset"))
    hl.bind(mainMod .. " + R",  hl.dsp.submap("reset"))
end)
hl.bind(mainMod .. " + R", hl.dsp.submap("resize"))  -- :: $mod+r -> enter resize mode

--------------------------------------------------------------------------------
-- Mouse  — Sway `floating_modifier $mod normal`
--------------------------------------------------------------------------------
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })  -- :: $mod + LMB drag
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })  -- :: $mod + RMB resize
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

--------------------------------------------------------------------------------
-- Media / brightness keys  — Sway pamixer + brightnessctl
-- :: Noctalia OSD pops automatically on PipeWire/brightness changes.
--------------------------------------------------------------------------------
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("pamixer --sink @DEFAULT_SINK@ -i 5"),          { repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("pamixer --sink @DEFAULT_SINK@ -d 5"),          { repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("pamixer --sink @DEFAULT_SINK@ --toggle-mute"))
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl set 5%+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 5%-"), { locked = true, repeating = true })


--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

-- :: Sway `for_window [app_id=...] floating enable`. In Hyprland, `class`
-- :: matches the Wayland app_id for native Wayland apps.
hl.window_rule({
    name  = "float-nautilus",
    match = { class = "^(org\\.gnome\\.Nautilus)$" },
    float = true,
})
hl.window_rule({
    name  = "float-qalculate",
    match = { class = "^(qalculate-gtk)$" },
    float = true,
})

-- Ignore maximize requests from all apps.
hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

-- Fix some dragging issues with XWayland
hl.window_rule({
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },
    no_focus = true,
})


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
    name  = "noctalia-blur",
    match = { namespace = "^(noctalia-(bar-content|launcher-overlay|notifications|osd|overview|dock|toast|desktop-widgets)-.*)$" },
    blur         = true,
    ignore_alpha = 0.6,   -- :: don't blur the transparent bar frame, only the capsules/panels
})

-- :: Dim the desktop behind the modal launcher / overview.
hl.layer_rule({
    name  = "noctalia-dim-modals",
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

-- :: Lid CLOSE -> disable eDP-1; suspend only if no external display (clamshell).
hl.bind("switch:on:Lid Switch",
    hl.dsp.exec_cmd("~/.config/hypr/scripts/lid-close.sh"),
    { locked = true })

-- :: Lid OPEN -> re-enable the laptop panel with its configured mode/position.
-- :: (Mirrors the MONITORS block above; keep them in sync, or swap the command
-- ::  for `hyprctl reload` to re-apply every monitor rule from config.)
hl.bind("switch:off:Lid Switch",
    hl.dsp.exec_cmd([[hyprctl keyword monitor "eDP-1, 1920x1080, 2560x180, 1"]]),
    { locked = true })
