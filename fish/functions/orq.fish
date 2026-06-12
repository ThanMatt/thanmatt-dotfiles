function orq
    # :: org notes query via claude haiku
    if test (count $argv) -eq 0
        echo "Usage: orq <question>"
        return 1
    end

    set query (string join " " $argv)
    set notes_content (cat ~/notes/**/*.org 2>/dev/null)
    set token_estimate (string length $notes_content | awk '{print int($1/4)}')

    echo "Querying ~$token_estimate tokens of notes..."

    claude --model claude-haiku-4-5 --print \
        "You are the user's second brain. Their org-mode notes are below.
- For fact lookups: answer directly and cite the file/heading
- For connecting ideas: surface non-obvious links across notes
- For summaries: structure by theme, not by file

Question: $query

--- NOTES START ---
$notes_content
--- NOTES END ---"
end
