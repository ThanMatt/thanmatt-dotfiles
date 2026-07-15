function trash-cleanup-linux --description 'Purge trash-cli files older than 15 days (manual run, Linux)'
    # :: thin wrapper -- real logic lives in the dotfiles scripts/ dir
    ~/thanmatt-dotfiles/scripts/trash-cleanup-linux.fish $argv
end
