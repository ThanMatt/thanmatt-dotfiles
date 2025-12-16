function tmux-resurrect-fix
    set resurrect_dir ~/.local/share/tmux/resurrect

    # :: Check if directory exists
    if not test -d $resurrect_dir
        echo "Error: Resurrect directory not found at $resurrect_dir"
        return 1
    end

    cd $resurrect_dir

    # :: Check if 'last' symlink exists
    if not test -L last
        echo "Error: 'last' symlink not found"
        return 1
    end

    # :: Check if the symlinked file is 0 bytes
    if test -s last
        echo "✓ Resurrect file is healthy (not empty)"
        return 0
    end

    echo "⚠ Found empty resurrect file, fixing..."

    # :: Delete the empty file that 'last' points to
    set target_file (readlink last)
    rm -f $target_file
    rm -f last

    # :: Find the latest non-empty resurrect file
    set latest_file (ls -t tmux_resurrect_*.txt 2>/dev/null | while read file
        if test -s $file
            echo $file
            break
        end
    end)

    if test -z "$latest_file"
        echo "Error: No valid resurrect files found"
        return 1
    end

    # :: Create new symlink
    ln -s $latest_file last
    echo "✓ Fixed: 'last' now points to $latest_file"
end
