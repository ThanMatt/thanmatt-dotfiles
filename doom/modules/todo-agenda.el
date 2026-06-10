;;; todo-agenda.el --- Daily Todo Agenda for Doom Emacs -*- lexical-binding: t; -*-

;; :: Directory where daily agenda files are stored
(defvar todo-agenda-directory "~/org-notes/agenda"
  "Directory where daily todo-agenda org files are stored.")

;; :: Ensure agenda directory exists
(unless (file-exists-p todo-agenda-directory)
  (make-directory todo-agenda-directory t))

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

(defun todo-agenda--previous-todos-block (file)
  ":: Return the verbatim text under the \"* Todos\" heading of FILE.
The content and formatting are preserved exactly as written
(checklists, plain lines, indentation, sub-items, etc.); the block
stops at the next top-level heading and trailing blank lines are
trimmed.  Returns nil when FILE is missing or its Todos section is
empty."
  (when (and file (file-readable-p file))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      ;; :: Jump past the Todos heading, capture up to the next heading.
      (when (re-search-forward "^\\* Todos[ \t]*$" nil t)
        (forward-line 1)
        (let ((start (point)))
          (if (re-search-forward "^\\* " nil t)
              (goto-char (match-beginning 0))
            (goto-char (point-max)))
          (let ((block (string-trim-right
                        (buffer-substring-no-properties start (point)))))
            (unless (string-empty-p (string-trim block))
              block)))))))

(defun todo-agenda--ensure-file ()
  ":: Ensure today's agenda file exists and return its path.
The file is named after the current date (YYYY-MM-DD.org). When a new
file is created, unfinished todos from the most recent previous agenda
are carried over.  Emits a status message and returns the filepath."
  (let* ((date (format-time-string "%Y-%m-%d"))
         (title (format-time-string "%A, %B %d, %Y"))
         (filename (format "%s.org" date))
         (filepath (expand-file-name filename todo-agenda-directory))
         (file-exists (file-exists-p filepath))
         ;; :: Verbatim Todos block from the most recent previous agenda.
         (carried (unless file-exists
                    (todo-agenda--previous-todos-block
                     (todo-agenda--latest-previous-file date)))))

    ;; :: Create file if it doesn't exist
    (unless file-exists
      (with-temp-file filepath
        (insert (format "#+TITLE: %s\n" title))
        (insert (format "#+DATE: %s\n\n" date))
        (insert "* Todos\n")
        ;; :: Copy the previous agenda's Todos content as-is, or seed an empty one.
        (if carried
            (insert carried "\n")
          (insert "- [ ] \n"))
        (insert "\n* Notes\n\n")))

    ;; :: Display message
    (if file-exists
        (message "Opened today's agenda (%s)" date)
      (if carried
          (message "Created new agenda for %s (carried over previous todos)" date)
        (message "Created new agenda for %s" date)))
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

;; :: Key binding: SPC o a
(map! :leader
      :desc "Open Todo Agenda"
      "o a" #'todo-agenda)

(provide 'todo-agenda)
;;; todo-agenda.el ends here
