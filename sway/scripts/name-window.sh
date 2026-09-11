#!/bin/sh

# :: Label the focused window's title bar, e.g. to tell two Chrome windows in a
# :: stacked group apart (an incognito window has the same app_id, pid and title
# :: as a normal one, so no for_window rule can match it automatically).
# :: Driven by the Noctalia launcher: Super+Space, then `/name <label>` — see
# :: shell.launcher.dmenu.entry.namewindow in ../../noctalia-v5/config.toml.
# ::
# :: title_format only changes what sway draws; %title keeps following the page
# :: title. It's runtime-only and dies with the window. `/name -` resets it.

[ -n "$1" ] || exit 0
if [ "$1" = "-" ]; then
    swaymsg 'title_format "%title"'
else
    swaymsg "title_format \"$1 · %title\""
fi
