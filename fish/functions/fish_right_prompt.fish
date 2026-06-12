function fish_right_prompt
  # :: emacs-libvterm mishandles right-aligned prompt redraws (cursor math
  # :: drifts on every keystroke/autosuggestion -> the "seizure"). Skip it.
  if string match -q '*vterm*' -- "$INSIDE_EMACS"
    return
  end
  _r20_prompt right
end
