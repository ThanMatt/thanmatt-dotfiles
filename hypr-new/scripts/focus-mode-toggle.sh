#!/usr/bin/env fish

# :: Hyprland equivalent of Sway's `focus mode_toggle` — jump between the
# :: floating and tiled window "layers" on the current workspace.
# ::
# :: Why a script: Hyprland's movefocus (hl.dsp.focus{direction=...}) never
# :: crosses the float/tile boundary. Verified on 0.56 — from a tiled window,
# :: `movefocus` toward a floating window skips it (and can jump monitors);
# :: from a floating window it does nothing at all. `cyclenext` with an explicit
# :: floating/tiled filter is the only dispatcher that crosses over.

if test (hyprctl -j activewindow | jq -r .floating) = true
    # :: on a floating window -> back down to the tiled layer
    hyprctl dispatch 'hl.dsp.window.cycle_next({ tiled = true })'
else
    # :: on a tiled window -> up to the floating layer
    hyprctl dispatch 'hl.dsp.window.cycle_next({ floating = true })'
end
