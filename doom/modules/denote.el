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

;; :: `denote-link' only inserts. This copies a [[denote:ID][Title]] link to the
;; :: kill ring + CLIPBOARD (same pairing as `my/copy-region-as-org-link') for
;; :: pasting into another note. Always Org syntax, since that's where it lands.
(defun my/denote-copy-link (&optional pick)
  "Copy an Org denote: link to the current note.
When the buffer isn't a Denote note, or with prefix arg PICK, prompt for one.
An active region becomes the link description."
  (interactive "P")
  (require 'denote)
  (let* ((current (buffer-file-name))
         (file (if (and (not pick) current (denote-file-is-note-p current))
                   current
                 (denote-file-prompt nil "Copy link to note")))
         (link (denote-format-link file (denote-get-link-description file) 'org nil)))
    (kill-new link)
    (gui-set-selection 'CLIPBOARD link)
    (message "Copied → %s" link)))

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
