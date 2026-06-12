;;; todo-agenda.el --- Daily Todo Agenda for Doom Emacs -*- lexical-binding: t; -*-

;; :: Mirrors `my/daily-agenda' (see org-agenda.el) for file path, naming, and
;; :: template, but adds one extra behaviour: unfinished TODOs from the most
;; :: recent previous agenda are carried over into the TODOs section.

;; :: Directory where daily agenda files are stored (matches `my/daily-agenda')
(defvar todo-agenda-directory (expand-file-name "agendas/" my/notes-dir)
  "Directory where daily agenda org files are stored.")

(defun todo-agenda--latest-previous-file (date)
  ":: Return the path of the most recent agenda file dated before DATE, or nil.
DATE is a YYYY-MM-DD string; filenames sort lexicographically by date."
  (let* ((dir (expand-file-name todo-agenda-directory))
         (files (when (file-directory-p dir)
                  (directory-files dir t "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\.org\\'"))))
    ;; :: Keep only files strictly before today, newest last, then take the last.
    (car (last (seq-filter (lambda (f)
                             (string< (file-name-base f) date))
                           (sort files #'string<))))))

(defun todo-agenda--todos-content (file)
  ":: Return the raw text under the \"* TODOs\" heading of FILE, verbatim.
Everything between the heading and the next top-level heading is copied
as-is (preserving formatting, sub-items, and checked state), with only
surrounding blank lines trimmed.  Returns nil when there is nothing."
  (when (and file (file-readable-p file))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      ;; :: Capture from just after the TODOs heading to the next heading.
      (when (re-search-forward "^\\* TODOs[ \t]*$" nil t)
        (forward-line 1)
        (let ((start (point)))
          (if (re-search-forward "^\\* " nil t)
              (goto-char (match-beginning 0))
            (goto-char (point-max)))
          (let ((content (string-trim (buffer-substring-no-properties start (point)))))
            (unless (string-empty-p content)
              content)))))))

(defun todo-agenda--ensure-file ()
  ":: Create or open today's agenda file and return its path.
Replicates `my/daily-agenda's path, naming, navigation links, and
section layout, then carries over unfinished TODOs from the most
recent previous agenda."
  (let* ((today (format-time-string "%Y-%m-%d"))
         (filename (format "%s.org" today))
         (filepath (expand-file-name filename todo-agenda-directory))
         (file-exists (file-exists-p filepath))
         (agenda-dir (expand-file-name todo-agenda-directory))
         (all-agendas (when (file-directory-p agenda-dir)
                        (directory-files agenda-dir nil "^[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\.org$")))
         (sorted-agendas (sort all-agendas #'string<))
         (current-index (cl-position filename sorted-agendas :test #'string=))
         (prev-file (when (and current-index (> current-index 0))
                      (nth (1- current-index) sorted-agendas)))
         (next-file (when (and current-index (< current-index (1- (length sorted-agendas))))
                      (nth (1+ current-index) sorted-agendas))))

    ;; :: Ensure directory exists
    (make-directory (file-name-directory filepath) t)

    ;; :: Open or create the file WITHOUT selecting it, so callers control
    ;; :: which window it ends up in (avoids it appearing in the current window
    ;; :: as well as a side window).
    (with-current-buffer (find-file-noselect filepath)
      ;; :: If file doesn't exist, create template
      (unless file-exists
        (let ((carried (todo-agenda--todos-content
                        (todo-agenda--latest-previous-file today))))
          (insert (format "#+TITLE: Daily Agenda - %s\n" today))
          (insert (format "#+DATE: %s\n\n" today))

          ;; :: Add navigation links
          (when (or prev-file next-file)
            (when prev-file
              (insert (format "[[./%s][← Previous]] " prev-file)))
            (when next-file
              (insert (format "[[./%s][Next →]]" next-file)))
            (insert "\n\n"))

          (insert "* TODOs\n\n")
          ;; :: Copy the previous agenda's TODOs block verbatim, then leave a
          ;; :: fresh placeholder for new items.
          (if carried
              (insert carried "\n- [ ] \n\n")
            (insert "- [ ] \n\n"))
          (insert "* Meetings\n\n\n")
          (insert "* Notes\n\n")
          (goto-char (point-min))
          (re-search-forward "- \\[ \\] " nil t)
          (if carried
              (message "Created new daily agenda for %s (carried over previous TODOs)" today)
            (message "Created new daily agenda for %s" today)))))
    filepath))

(defun todo-agenda ()
  ":: Open or create today's agenda file in the current window."
  (interactive)
  (find-file (todo-agenda--ensure-file)))

(defun todo-agenda-side ()
  ":: Open or create today's agenda in an editable right side window.
Reuses the same file logic as `todo-agenda', but displays it in a
persistent side split (like Claude Code) and focuses it for editing."
  (interactive)
  (let* ((filepath (todo-agenda--ensure-file))
         (buf (find-file-noselect filepath)))
    (my/focus-window (my/display-in-side buf 'right 0 0.40))))

;; :: Key bindings live in modules/keybindings.el (under the "d" dev prefix)
;; :: to avoid clashing with Doom's built-in "SPC o a" org-agenda prefix.

(provide 'todo-agenda)
;;; todo-agenda.el ends here
