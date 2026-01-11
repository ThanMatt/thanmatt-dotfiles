function strdiff
    diff -u (echo $argv[1] | psub) (echo $argv[2] | psub) | delta
end
