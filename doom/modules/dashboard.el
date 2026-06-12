;;; dashboard.el --- Dashboard customizations -*- lexical-binding: t; -*-

;; :: ============================================================
;; :: Doom Dashboard Menu Customizations
;; :: ============================================================

(defun my/open-org-directory ()
  "Open the org directory in dired for navigation."
  (interactive)
  (dired org-directory))

;; :: Saved GitLab issue files. Set GITLAB_ISSUES_DIR to your real path (the
;; :: same var gitlab.el reads); defaults to issues/ in the notes dir.
(defun my/open-gitlab-issues-directory ()
  "Open the GitLab issues directory in dired for navigation."
  (interactive)
  (dired (expand-file-name (or (getenv "GITLAB_ISSUES_DIR")
                               (expand-file-name "issues/" my/notes-dir)))))

(defun my/open-knowledgebase ()
  "Open the knowledgebase directory."
  (interactive)
  (dired my/notes-dir))

(defun my/open-cheatsheet ()
  "Open cheatsheet in a side window for quick reference and editing."
  (interactive)
  (let* ((cheatsheet-file (expand-file-name "cheatsheet.org" my/notes-dir))
         (buffer (find-file-noselect cheatsheet-file)))
    (unless (file-exists-p cheatsheet-file)
      (with-current-buffer buffer
        (insert "* Cheatsheet\n\n")
        (insert "** Emacs Keybindings\n")
        (insert "- SPC o d :: Open Org Directory\n")
        (insert "- SPC o i :: Open GitLab Issues\n")
        (insert "- SPC o C :: Open this Cheatsheet\n\n")
        (insert "** Custom Notes\n")
        (insert "Add your notes here...\n")
        (save-buffer)))
    (pop-to-buffer buffer
                   '((display-buffer-at-bottom)
                     (window-height . 0.4)
                     (side . bottom)
                     (slot . 0)))
    (org-mode)))

(defun my/copy-link-at-point ()
  "Copy the URL of the org link at point to clipboard."
  (interactive)
  (if (org-in-regexp org-link-bracket-re 1)
      (let ((url (org-element-property :raw-link (org-element-context))))
        (kill-new url)
        (message "Copied: %s" url))
    (message "No link at point")))

;; :: Keybindings
;; :: NOTE: GitLab Issues is on "I" (shift-i) because modules/inventory.el binds
;; :: "SPC o i" to the inventory tracker; this keeps both reachable on both OSes.
(map! :leader
      :prefix "o"
      :desc "Open Org Directory" "d" #'my/open-org-directory
      :desc "Open GitLab Issues" "I" #'my/open-gitlab-issues-directory
      :desc "Open Cheatsheet" "C" #'my/open-cheatsheet)

(map! :after org
      :map org-mode-map
      :localleader
      :prefix ("l" . "link")
      :desc "Copy link URL" "y" #'my/copy-link-at-point)

;; :: Dashboard menu sections (add or remove items here). Actions referencing
;; :: inventory/finance resolve lazily against modules/{inventory,finance}.el.
(setq +doom-dashboard-menu-sections
      '(("Reload last session"
         :icon (nerd-icons-octicon "nf-oct-history" :face 'doom-dashboard-menu-title)
         :when (cond ((modulep! :ui workspaces)
                      (file-exists-p (expand-file-name persp-auto-save-fname persp-save-dir)))
                     ((require 'desktop nil t)
                      (file-exists-p (desktop-full-file-name))))
         :action doom/quickload-session)
        ("Open Agenda"
         :icon (nerd-icons-octicon "nf-oct-calendar" :face 'doom-dashboard-menu-title)
         :when (fboundp 'org-agenda)
         :action org-agenda)
        ("Show Org Directory"
         :icon (nerd-icons-faicon "nf-fa-folder_open" :face 'doom-dashboard-menu-title)
         :action my/open-org-directory)
        ("Knowledgebase"
         :icon (nerd-icons-octicon "nf-oct-book" :face 'doom-dashboard-menu-title)
         :action my/open-knowledgebase)
        ("Saved GitLab Issues"
         :icon (nerd-icons-faicon "nf-fa-gitlab" :face 'doom-dashboard-menu-title)
         :action my/open-gitlab-issues-directory)
        ("Show GitLab Todos"
         :icon (nerd-icons-faicon "nf-fa-check_square_o" :face 'doom-dashboard-menu-title)
         :action my/gitlab-fetch-todos)
        ("Open Inventory"
         :icon (nerd-icons-octicon "nf-oct-package" :face 'doom-dashboard-menu-title)
         :action inventory/open-or-create)
        ("Current Financials"
         :icon (nerd-icons-octicon "nf-oct-graph" :face 'doom-dashboard-menu-title)
         :action finance/create-expense-tracker)
        ("Open Cheatsheet"
         :icon (nerd-icons-faicon "nf-fa-book" :face 'doom-dashboard-menu-title)
         :action my/open-cheatsheet)
        ("Open project"
         :icon (nerd-icons-octicon "nf-oct-briefcase" :face 'doom-dashboard-menu-title)
         :action projectile-switch-project)
        ("Recently opened files"
         :icon (nerd-icons-octicon "nf-oct-file" :face 'doom-dashboard-menu-title)
         :action recentf-open-files)
        ("Jump to bookmark"
         :icon (nerd-icons-octicon "nf-oct-bookmark" :face 'doom-dashboard-menu-title)
         :action bookmark-jump)))

(provide 'dashboard)
;;; dashboard.el ends here
