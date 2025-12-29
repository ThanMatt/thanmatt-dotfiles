function vat
    set selected (fd --type f | fzf --preview="bat --color=always --style=numbers {}")
    and vi $selected
end
