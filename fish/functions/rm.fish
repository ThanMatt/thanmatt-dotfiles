# :: soft-delete swap, shadows rm interactively and forwards to trash-cli
function rm --description 'soft delete via trash-cli, use `command rm` for the real thing'
    # :: trash-put mirrors rm's flag behavior closely enough (-r, -f, -v all work)
    trash-put $argv
end
