function strdiff
    # :: Base is shown as "old", second arg as "new"
    git diff --no-index --word-diff-regex=. (echo $argv[1] | psub) (echo $argv[2] | psub)
end
