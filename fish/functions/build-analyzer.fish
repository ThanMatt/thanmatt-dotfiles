function build-analyzer --description "Analyze build directory sizes with breakdown"
    # Check if directory argument is provided, default to current directory
    set target_dir (test (count $argv) -gt 0; and echo $argv[1]; or echo ".")

    # Check if directory exists
    if not test -d $target_dir
        echo "❌ Directory '$target_dir' does not exist"
        return 1
    end

    echo "📊 Build Analysis for: $target_dir"
    echo "=" | string repeat 50

    # Get total size
    set total_size (du -sh $target_dir | cut -f1)
    set total_bytes (du -sb $target_dir | cut -f1)

    echo "🗂️  Total Size: $total_size"
    echo ""

    # JavaScript files
    set js_files (find $target_dir -name "*.js" -type f 2>/dev/null)
    if test (count $js_files) -gt 0
        set js_size_bytes (du -cb $js_files | tail -1 | cut -f1)
        set js_size_human (echo $js_size_bytes | numfmt --to=iec-i --suffix=B)
        set js_percent (math "round($js_size_bytes * 100 / $total_bytes)")
        echo "🟨 JavaScript: $js_size_human ($js_percent%)"
    else
        echo "🟨 JavaScript: 0B (0%)"
        set js_size_bytes 0
    end

    # CSS files
    set css_files (find $target_dir -name "*.css" -type f 2>/dev/null)
    if test (count $css_files) -gt 0
        set css_size_bytes (du -cb $css_files | tail -1 | cut -f1)
        set css_size_human (echo $css_size_bytes | numfmt --to=iec-i --suffix=B)
        set css_percent (math "round($css_size_bytes * 100 / $total_bytes)")
        echo "🎨 CSS: $css_size_human ($css_percent%)"
    else
        echo "🎨 CSS: 0B (0%)"
        set css_size_bytes 0
    end

    # Image files
    set image_files (find $target_dir \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.gif" -o -name "*.webp" -o -name "*.svg" -o -name "*.avif" \) -type f 2>/dev/null)
    if test (count $image_files) -gt 0
        set img_size_bytes (du -cb $image_files | tail -1 | cut -f1)
        set img_size_human (echo $img_size_bytes | numfmt --to=iec-i --suffix=B)
        set img_percent (math "round($img_size_bytes * 100 / $total_bytes)")
        echo "🖼️  Images: $img_size_human ($img_percent%)"

        # Show largest images
        echo "   📸 Largest images:"
        find $target_dir \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.gif" -o -name "*.webp" -o -name "*.svg" -o -name "*.avif" \) -type f -exec du -h {} \; | sort -hr | head -3 | while read size file
            set filename (basename $file)
            echo "      • $filename: $size"
        end
    else
        echo "🖼️  Images: 0B (0%)"
        set img_size_bytes 0
    end

    # Other assets (everything else)
    set other_bytes (math "$total_bytes - $js_size_bytes - $css_size_bytes - $img_size_bytes")
    set other_human (echo $other_bytes | numfmt --to=iec-i --suffix=B)
    set other_percent (math "round($other_bytes * 100 / $total_bytes)")
    echo "📦 Other: $other_human ($other_percent%)"

    echo ""
    echo "🔍 File count breakdown:"
    echo "   JS files: "(count $js_files)
    echo "   CSS files: "(count $css_files)
    echo "   Images: "(count $image_files)
    echo "   Total files: "(find $target_dir -type f | wc -l)
end
