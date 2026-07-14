function trash-cleanup --description 'Purge trash-cli files older than 15 days (manual run)'
    # :: thin wrapper -- real logic lives in the dotfiles scripts/ dir
    ~/thanmatt-dotfiles/scripts/trash-cleanup.fish $argv
end
