;;; denote.el --- Denote reference notes + journal -*- lexical-binding: t; -*-

;; :: Reference notes (meeting notes, feedback, feature writeups) and dailies,
;; :: deliberately kept OUT of `org-agenda-files' so braindumps can't pollute
;; :: the agenda. Notes live under `my/notes-dir'/notes/; journal under
;; :: notes/journal/. See modules/org-agenda.el for capture templates.

(use-package! denote
  :hook (dired-mode . denote-dired-mode)
  :init
  (setq denote-directory (expand-file-name "notes/" my/notes-dir))
  :config
  (setq denote-known-keywords '("meeting" "feedback" "feature" "idea" "work")
        denote-infer-keywords t
        denote-sort-keywords t
        denote-date-prompt-use-org-read-date t)
  ;; :: buffer name shows the note title instead of the timestamp filename
  (denote-rename-buffer-mode 1))

(use-package! consult-denote
  :after denote
  :config (consult-denote-mode 1))

(use-package! denote-journal
  :commands (denote-journal-new-entry denote-journal-new-or-existing-entry)
  :config
  (setq denote-journal-directory (expand-file-name "journal" denote-directory)
        denote-journal-keyword "journal"
        denote-journal-title-format 'day-date-month-year))

(provide 'denote)
;;; denote.el ends here
