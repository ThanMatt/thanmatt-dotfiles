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

(defun todo-agenda--unfinished-todos (file)
  ":: Return a list of unfinished todo lines (\"- [ ] ...\") from FILE.
Only lines under the \"* Todos\" heading are considered, and empty
placeholder todos are skipped."
  (when (and file (file-readable-p file))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (let ((todos '()))
        ;; :: Jump to the Todos heading, stop at the next heading.
        (when (re-search-forward "^\\* Todos[ \t]*$" nil t)
          (forward-line 1)
          (while (and (not (eobp))
                      (not (looking-at "^\\* ")))
            (when (looking-at "^[ \t]*- \\[ \\] \\(.+?\\)[ \t]*$")
              (push (string-trim (match-string 1)) todos))
            (forward-line 1)))
        (nreverse todos)))))

(defun todo-agenda ()
  "Open or create today's agenda file.
The file is named after the current date (YYYY-MM-DD.org). If today's
agenda already exists it is opened instead of being recreated.  When a
new file is created, unfinished todos from the most recent previous
agenda are carried over."
  (interactive)
  (let* ((date (format-time-string "%Y-%m-%d"))
         (title (format-time-string "%A, %B %d, %Y"))
         (filename (format "%s.org" date))
         (filepath (expand-file-name filename todo-agenda-directory))
         (file-exists (file-exists-p filepath)))

    ;; :: Create file if it doesn't exist
    (unless file-exists
      (let ((carried (todo-agenda--unfinished-todos
                      (todo-agenda--latest-previous-file date))))
        (with-temp-file filepath
          (insert (format "#+TITLE: %s\n" title))
          (insert (format "#+DATE: %s\n\n" date))
          (insert "* Todos\n")
          ;; :: Carry over unfinished todos from the previous agenda.
          (dolist (todo carried)
            (insert (format "- [ ] %s\n" todo)))
          (insert "- [ ] \n\n")
          (insert "* Notes\n\n"))))

    ;; :: Open the file
    (find-file filepath)

    ;; :: Display message
    (if file-exists
        (message "Opened today's agenda (%s)" date)
      (let ((carried (todo-agenda--unfinished-todos
                      (todo-agenda--latest-previous-file date))))
        (if carried
            (message "Created new agenda for %s (carried over %d todo%s)"
                     date (length carried) (if (= (length carried) 1) "" "s"))
          (message "Created new agenda for %s" date))))))

;; :: Key binding: SPC o a
(map! :leader
      :desc "Open Todo Agenda"
      "o a" #'todo-agenda)

(provide 'todo-agenda)
;;; todo-agenda.el ends here
