function git_copy_unstaged
    if test (count $argv) -eq 0
        echo "Usage: git_copy_unstaged <destination_folder>"
        return 1
    end

    set dest_folder $argv[1]

    # Create destination folder if it doesn't exist
    mkdir -p "$dest_folder"

    # Get unstaged files (modified and untracked)
    set unstaged_files (git status --porcelain | grep -E '^ M|^\?\?' | cut -c4-)

    if test (count $unstaged_files) -eq 0
        echo "No unstaged files found"
        return 0
    end

    echo "Copying unstaged files to $dest_folder:"
    for file in $unstaged_files
        if test -f "$file"
            # Copy just the file without directory structure
            set filename (basename "$file")
            cp "$file" "$dest_folder/$filename"
            echo "  $filename"
        end
    end

    echo "Done! Copied "(count $unstaged_files)" files to $dest_folder"
end

# Create an alias for easier use
alias gcu git_copy_unstaged
