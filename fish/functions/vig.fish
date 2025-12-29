function vig
    set selected (rg --color=always --line-number --no-heading --smart-case "" | \
        fzf --ansi \
            --delimiter : \
            --preview 'bat --color=always {1} --highlight-line {2}' \
            --preview-window 'up,60%,border-bottom,+{2}+3/3,~3')

    and begin
        set file (echo $selected | cut -d: -f1)
        set line (echo $selected | cut -d: -f2)
        vi +$line $file
    end
end
