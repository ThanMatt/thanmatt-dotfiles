;;; org-agenda.el --- Org-mode and agenda customizations -*- lexical-binding: t; -*-

;; :: ============================================================
;; :: Org Agenda & Calendar Integration
;; :: ============================================================

;; :: Configure org-agenda files
(after! org
  (setq org-agenda-files (list (expand-file-name "agenda.org" my/notes-dir)
                               (expand-file-name "meetings.org" my/notes-dir)
                               (expand-file-name "agendas/" my/notes-dir))))

;; :: Time format configuration
(after! org
  (setq org-agenda-timegrid-use-ampm t
        org-agenda-time-leading-zero nil))  ;; :: "9:00am" instead of "09:00am"

;; :: Create or open today's agenda file
(defun my/daily-agenda ()
  "Create or open today's agenda file with structured sections."
  (interactive)
  (let* ((today (format-time-string "%Y-%m-%d"))
         (filename (format "%s.org" today))
         (filepath (expand-file-name filename (expand-file-name "agendas/" my/notes-dir)))
         (file-exists (file-exists-p filepath))
         (agenda-dir (expand-file-name "agendas/" my/notes-dir))
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

    ;; :: Open or create the file
    (find-file filepath)

    ;; :: If file doesn't exist, create template
    (unless file-exists
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
      (insert "- [ ] \n\n")
      (insert "* Meetings\n\n\n")
      (insert "* Notes\n\n")
      (goto-char (point-min))
      (re-search-forward "- \\[ \\] " nil t)
      (message "Created new daily agenda for %s" today))))

;; :: Add capture template for meeting notes
(after! org
  (add-to-list 'org-capture-templates
               '("m" "Meeting Notes" entry
                 (file+headline "meetings.org" "Meetings")
                 "* %(or my/current-event-title \"Meeting\") - %U\n:PROPERTIES:\n:EVENT: %(or my/current-event-title \"\")\n:END:\n\n** Notes\n%?\n\n** Action Items\n- [ ] \n"
                 :empty-lines 1)))

;; :: Capture meeting notes from agenda
(after! org-agenda
  (defun my/capture-meeting-note ()
    "Capture meeting notes from agenda, pre-filling event title."
    (interactive)
    (let* ((marker (org-get-at-bol 'org-marker))
           (event-title (if marker
                            (org-with-point-at marker
                              (org-get-heading t t t t))
                          "Meeting")))
      (setq my/current-event-title event-title)
      (org-capture nil "m")))

  ;; :: Override AFTER evil-org-agenda loads its keys
  (after! evil-org-agenda
    (evil-define-key 'motion org-agenda-mode-map
      (kbd "n") #'my/capture-meeting-note
      (kbd "TAB") #'org-agenda-goto)))

;; :: Auto-refresh agenda view every 1 minute
(after! org-agenda
  (defun my/org-agenda-redo-in-other-window ()
    "Refresh org-agenda if it's visible in any window."
    (save-excursion
      (dolist (buffer (buffer-list))
        (with-current-buffer buffer
          (when (derived-mode-p 'org-agenda-mode)
            (org-agenda-redo t))))))

  (run-at-time "00:00" 60 'my/org-agenda-redo-in-other-window))

;; :: Force window navigation in org-agenda
(after! evil-org-agenda
  (evil-define-key 'motion org-agenda-mode-map
    (kbd "C-h") #'evil-window-left
    (kbd "C-j") #'evil-window-down
    (kbd "C-k") #'evil-window-up
    (kbd "C-l") #'evil-window-right))

(provide 'org-agenda)
;;; org-agenda.el ends here

