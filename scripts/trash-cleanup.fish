#!/opt/homebrew/bin/fish
# :: trash-cleanup.fish -- permanently purge trash-cli files older than
# :: $retention_days from ~/.local/share/Trash. Pairs with
# :: fish/functions/rm.fish, which redirects `rm` into the trash instead of
# :: deleting immediately.
# ::
# :: Runs on a launchd timer; see launchd/com.thanmatt.trash-cleanup.plist.

set -l retention_days 15

if not type -q trash-empty
    echo "trash-cleanup: trash-empty not found (brew install trash-cli?)" >&2
    exit 1
end

trash-empty -f $retention_days
echo "trash-cleanup: purged trash items older than $retention_days days ("(date "+%Y-%m-%d %H:%M")")"
