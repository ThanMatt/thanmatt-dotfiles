#!/bin/sh

# :: Sway equivalent of the `hl.env(...)` block in ../../hypr-new/hyprland.lua.
# :: Sway has no `env` config directive, and this session is launched by GDM, so
# :: neither ~/.config/environment.d nor an interactive fish shell reaches it --
# :: the session PATH is the bare /usr/local/bin:/usr/bin.
# ::
# :: Everything Noctalia spawns (launcher entries, widget commands, Emacs) is a
# :: child of Noctalia, so exporting here once covers the whole session:
# ::   exec ~/.config/sway/scripts/session-env.sh noctalia -d
# ::
# :: Usage: session-env.sh <command> [args...]

# :: Cargo/pip-installed CLIs live here but are not on the session PATH, so
# :: Noctalia widget commands (which run through /bin/sh) come back
# :: "command not found" even though they are on disk.
PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
export PATH

# :: doom/modules/gitlab.el reads these via getenv at Emacs startup, and Emacs is
# :: spawned by the launcher, not an interactive fish shell -- `set -Ux` in fish
# :: never reaches it.
export GITLAB_PROJECT_ID=53733314
export GITLAB_PROJECT_NAME=mos

# :: Safe everywhere, no condition needed.
export ELECTRON_OZONE_PLATFORM_HINT=wayland

# :: NVIDIA only. This repo also serves an Intel ThinkPad, where forcing the
# :: nvidia VA-API driver breaks hardware video decode -- hence the probe rather
# :: than unconditional exports (same check as hyprland.lua's has_nvidia()).
# :: NOTE: these reach CHILD processes only; sway's own renderer would need them
# :: set before sway starts (i.e. in the session entry, not here).
if [ -e /sys/module/nvidia_drm/parameters/modeset ]; then
  export LIBVA_DRIVER_NAME=nvidia
  export GBM_BACKEND=nvidia-drm
  export __GLX_VENDOR_LIBRARY_NAME=nvidia
fi

exec "$@"
