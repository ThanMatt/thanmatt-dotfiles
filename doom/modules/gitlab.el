;;; gitlab.el --- GitLab integration for Emacs -*- lexical-binding: t; -*-

;; :: ============================================================
;; :: GitLab Integration
;; :: ============================================================
;;
;; :: Setup Instructions:
;; :: 1. Set environment variables in your shell config (~/.zshrc, ~/.bashrc, or ~/.config/fish/config.fish):
;; ::    export GITLAB_URL="https://gitlab.com"  # or your company's GitLab URL
;; ::    export GITLAB_PROJECT_ID="your-project-id"  # find this in GitLab project settings
;; ::    export GITLAB_PROJECT_NAME="project-name"  # short name for your project (e.g., "myapp")
;; ::    export GITLAB_ISSUES_DIR="$HOME/notes/projects/myapp/issues"  # where to store issue files
;; ::
;; :: 2. Add your GitLab token to ~/.authinfo.gpg:
;; ::    machine gitlab.com login api password YOUR_GITLAB_TOKEN
;; ::
;; :: 3. Reload your Doom config: SPC h r r

;; :: Configuration variables (from environment)
(defvar my/gitlab-url (or (getenv "GITLAB_URL") "https://gitlab.com")
  "GitLab instance URL (set via GITLAB_URL env var)")

(defvar my/gitlab-project-id (getenv "GITLAB_PROJECT_ID")
  "Your GitLab project ID (set via GITLAB_PROJECT_ID env var)")

(defvar my/gitlab-project-name (or (getenv "GITLAB_PROJECT_NAME") "project")
  "Short name for your project (set via GITLAB_PROJECT_NAME env var)")

(defvar my/gitlab-issues-dir
  (expand-file-name
   (or (getenv "GITLAB_ISSUES_DIR")
       (format "%sprojects/%s/issues" my/notes-dir my/gitlab-project-name)))
  "Directory to store GitLab issue files (set via GITLAB_ISSUES_DIR env var)")

(defun my/gitlab-safe-title (title &optional max-length)
  "Sanitize TITLE for use in a filename, truncating to MAX-LENGTH (default 60)."
  (let* ((max (or max-length 60))
         (sanitized (replace-regexp-in-string "[:/\\?*|<>]" "-" title)))
    (string-trim-right
     (if (> (length sanitized) max) (substring sanitized 0 max) sanitized))))

(defun my/gitlab-escape-org-title (title)
  "Escape square brackets in TITLE so org-mode link syntax isn't broken."
  (replace-regexp-in-string "\\]" ")" (replace-regexp-in-string "\\[" "(" title)))

;; :: Validation helper
(defun my/gitlab-check-config ()
  "Check if required GitLab configuration is set."
  (unless my/gitlab-project-id
    (error "GITLAB_PROJECT_ID environment variable is not set. Please set it in your shell config.")))

(defun my/gitlab-get-token ()
  "Retrieve GitLab token from auth-source (secure storage)."
  (require 'auth-source)
  (let ((auth-info (auth-source-search :host "gitlab.com" :user "api" :max 1)))
    (if auth-info
        (funcall (plist-get (car auth-info) :secret))
      (error "GitLab token not found in auth-source. Please add it to ~/.authinfo.gpg"))))

(defun my/gitlab-fetch-issue (issue-id)
  "Fetch GitLab issue and insert link to local file at point.
If local file exists, link to it. Otherwise, create it first."
  (interactive "sGitLab Issue ID: ")
  (my/gitlab-check-config)
  (let* ((issues-dir my/gitlab-issues-dir)
         (existing-files (directory-files issues-dir nil (format "^%s#%s - .*\\.org$" my/gitlab-project-name issue-id)))
         (current-buffer (current-buffer)))

    (if existing-files
        ;; :: File exists, insert link to it
        (let* ((filename (car existing-files))
               (filepath (expand-file-name filename issues-dir))
               (title (replace-regexp-in-string (format "^%s#%s - \\(.*\\)\\.org$" my/gitlab-project-name issue-id) "\\1" filename))
               (display-text (format "%s#%s - %s" my/gitlab-project-name issue-id (my/gitlab-escape-org-title title)))
               (link-text
                (if (derived-mode-p 'org-mode)
                    (format "[[file:%s][%s]]" filepath display-text)
                  (format "[%s](%s)" display-text filepath))))
          (insert link-text)
          (message "Inserted link to existing file: %s" filename))

      ;; :: File doesn't exist, fetch and create it
      (let* ((token (my/gitlab-get-token))
             (project-id-encoded (url-hexify-string my/gitlab-project-id))
             (api-url (format "%s/api/v4/projects/%s/issues/%s"
                              my/gitlab-url
                              project-id-encoded
                              issue-id))
             (url-request-extra-headers
              `(("PRIVATE-TOKEN" . ,token)))
             (url-request-method "GET"))

        (url-retrieve api-url
                      (lambda (status)
                        (if (plist-get status :error)
                            (message "Error fetching issue: %s" (plist-get status :error))
                          (goto-char url-http-end-of-headers)
                          (let* ((json-object-type 'hash-table)
                                 (json-array-type 'list)
                                 (json-key-type 'string)
                                 (json (json-read))
                                 (title (gethash "title" json))
                                 (description (or (gethash "description" json) ""))
                                 (state (gethash "state" json))
                                 (labels (gethash "labels" json))
                                 (created-at (gethash "created_at" json))
                                 (updated-at (gethash "updated_at" json))
                                 (closed-at (gethash "closed_at" json))
                                 (assignees (gethash "assignees" json))
                                 (author (gethash "author" json))
                                 (web-url (gethash "web_url" json))
                                 (milestone (gethash "milestone" json))
                                 (safe-title (my/gitlab-safe-title title))
                                 (filename (format "%s#%s - %s.org" my/gitlab-project-name issue-id safe-title))
                                 (filepath (expand-file-name filename issues-dir)))

                            ;; :: Ensure directory exists
                            (make-directory issues-dir t)

                            ;; :: Convert markdown description to org using pandoc
                            (let ((org-description
                                   (if (string-empty-p description)
                                       ""
                                     (with-temp-buffer
                                       (insert description)
                                       (shell-command-on-region
                                        (point-min) (point-max)
                                        "pandoc -f markdown -t org"
                                        (current-buffer) t)
                                       (buffer-string)))))

                              ;; :: Create org file content
                              (with-temp-file filepath
                                (insert (format "#+TITLE: %s#%s - %s\n" my/gitlab-project-name issue-id title))
                                (insert (format "#+DATE: %s\n\n" (format-time-string "%Y-%m-%d")))
                                (insert (format "* Issue Details\n\n"))
                                (insert (format "- *Status:* %s\n" state))
                                (insert (format "- *URL:* [[%s][GitLab Issue #%s]]\n" web-url issue-id))
                                (when author
                                  (insert (format "- *Author:* %s\n" (gethash "name" author))))
                                (when labels
                                  (insert (format "- *Labels:* %s\n"
                                                (mapconcat 'identity labels ", "))))
                                (when milestone
                                  (insert (format "- *Milestone:* %s\n"
                                                (gethash "title" milestone))))
                                (when assignees
                                  (insert (format "- *Assignees:* %s\n"
                                                (mapconcat (lambda (a) (gethash "name" a))
                                                          assignees ", "))))
                                (insert (format "- *Created:* %s\n"
                                              (format-time-string "%Y-%m-%d %H:%M"
                                                                (date-to-time created-at))))
                                (insert (format "- *Updated:* %s\n"
                                              (format-time-string "%Y-%m-%d %H:%M"
                                                                (date-to-time updated-at))))
                                (when closed-at
                                  (insert (format "- *Closed:* %s\n"
                                                (format-time-string "%Y-%m-%d %H:%M"
                                                                  (date-to-time closed-at)))))
                                (insert "\n* Description\n\n")
                                (insert org-description)
                                (insert "\n\n* Notes\n\n"))

                              ;; :: Insert link to the created file
                              (with-current-buffer current-buffer
                                (let* ((display-text (format "%s#%s - %s" my/gitlab-project-name issue-id (my/gitlab-escape-org-title title)))
                                       (link-text
                                        (if (derived-mode-p 'org-mode)
                                            (format "[[file:%s][%s]]" filepath display-text)
                                          (format "[%s](%s)" display-text filepath))))
                                  (insert link-text)
                                  (message "Created file and inserted link: %s" filename)))))))
                      nil t)))))

(defun my/gitlab-mark-todo-done (todo-id)
  "Mark a GitLab todo as done via API."
  (let* ((token (my/gitlab-get-token))
         (api-url (format "%s/api/v4/todos/%s/mark_as_done" my/gitlab-url todo-id))
         (url-request-extra-headers
          `(("PRIVATE-TOKEN" . ,token)))
         (url-request-method "POST"))

    (url-retrieve api-url
                  (lambda (status)
                    (if (plist-get status :error)
                        (message "Error marking todo as done: %s" (plist-get status :error))
                      (message "Marked todo #%s as done" todo-id)))
                  nil t)))

(defun my/gitlab-mark-todo-pending (todo-id)
  "Mark a GitLab todo as pending via API."
  (let* ((token (my/gitlab-get-token))
         (api-url (format "%s/api/v4/todos/%s/mark_as_pending" my/gitlab-url todo-id))
         (url-request-extra-headers
          `(("PRIVATE-TOKEN" . ,token)))
         (url-request-method "POST"))

    (url-retrieve api-url
                  (lambda (status)
                    (if (plist-get status :error)
                        (message "Error marking todo as pending: %s" (plist-get status :error))
                      (message "Marked todo #%s as pending" todo-id)))
                  nil t)))

(defun my/gitlab-todos-toggle-at-point ()
  "Toggle todo at point between done and pending."
  (interactive)
  (let ((todo-id (get-text-property (point) 'todo-id))
        (todo-state (get-text-property (point) 'todo-state)))
    (unless todo-id
      ;; :: Try to find todo-id in current line
      (save-excursion
        (beginning-of-line)
        (let ((line-end (line-end-position)))
          (while (and (< (point) line-end) (not todo-id))
            (setq todo-id (get-text-property (point) 'todo-id))
            (setq todo-state (get-text-property (point) 'todo-state))
            (forward-char 1)))))

    (if todo-id
        (progn
          ;; :: Toggle based on current state
          (if (string= todo-state "done")
              (my/gitlab-mark-todo-pending todo-id)
            (my/gitlab-mark-todo-done todo-id))

          ;; :: Remove from buffer
          (let ((inhibit-read-only t))
            (save-excursion
              (let ((start (progn
                             (beginning-of-line)
                             (while (and (not (bobp))
                                         (or (get-text-property (point) 'todo-id)
                                             (get-text-property (1- (point)) 'todo-id)
                                             (and (> (point) (point-min))
                                                  (not (looking-at "^•")))))
                               (forward-line -1))
                             (when (looking-at "^•")
                               (point))))
                    (end (progn
                           (beginning-of-line)
                           (forward-line 1)
                           (while (and (not (eobp))
                                       (not (looking-at "^•"))
                                       (not (looking-at "^No todos")))
                             (forward-line 1))
                           (point))))
                (when (and start end)
                  (delete-region start end))))))
      (message "No todo at point"))))

(defvar-local my/gitlab-todos-type-filter nil
  "Type filter used for the current todos buffer.")

(defvar-local my/gitlab-todos-state-filter nil
  "State filter used for the current todos buffer (pending or done).")

(defun my/gitlab-todos-refresh ()
  "Refresh the current GitLab todos buffer."
  (interactive)
  (my/gitlab-fetch-todos my/gitlab-todos-type-filter my/gitlab-todos-state-filter))

(defun my/gitlab-todos-filter-all ()
  "Show all pending todos."
  (interactive)
  (my/gitlab-fetch-todos nil nil))

(defun my/gitlab-todos-filter-completed ()
  "Show completed todos."
  (interactive)
  (my/gitlab-fetch-todos nil "done"))

(defun my/gitlab-todos-filter-issues ()
  "Show pending issue todos."
  (interactive)
  (my/gitlab-fetch-todos "Issue" nil))

(defun my/gitlab-todos-filter-merge-requests ()
  "Show pending merge request todos."
  (interactive)
  (my/gitlab-fetch-todos "MergeRequest" nil))

(defvar gitlab-todos-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "d") 'my/gitlab-todos-toggle-at-point)
    (define-key map (kbd "RET") 'my/gitlab-todos-toggle-at-point)
    (define-key map (kbd "r") 'my/gitlab-todos-refresh)
    (define-key map (kbd "a") 'my/gitlab-todos-filter-all)
    (define-key map (kbd "c") 'my/gitlab-todos-filter-completed)
    (define-key map (kbd "i") 'my/gitlab-todos-filter-issues)
    (define-key map (kbd "m") 'my/gitlab-todos-filter-merge-requests)
    (define-key map (kbd "q") 'quit-window)
    map)
  "Keymap for GitLab todos buffer.")

(define-derived-mode gitlab-todos-mode special-mode "GitLab-Todos"
  "Major mode for GitLab todos buffer.
\\{gitlab-todos-mode-map}"
  (setq truncate-lines t))

;; :: EVIL mode bindings
(with-eval-after-load 'evil
  (evil-set-initial-state 'gitlab-todos-mode 'normal)
  (evil-define-key 'normal gitlab-todos-mode-map
    (kbd "d") 'my/gitlab-todos-toggle-at-point
    (kbd "RET") 'my/gitlab-todos-toggle-at-point
    (kbd "r") 'my/gitlab-todos-refresh
    (kbd "gr") 'my/gitlab-todos-refresh
    (kbd "a") 'my/gitlab-todos-filter-all
    (kbd "c") 'my/gitlab-todos-filter-completed
    (kbd "i") 'my/gitlab-todos-filter-issues
    (kbd "m") 'my/gitlab-todos-filter-merge-requests
    (kbd "q") 'quit-window))

;; :: Global keybindings for GitLab functions
(map! :leader
      :prefix "o"
      :desc "GitLab Todos" "t" #'my/gitlab-fetch-todos
      :desc "GitLab Fetch Issue" "g i" #'my/gitlab-fetch-issue
      :desc "GitLab Lookup Issue" "g l" #'my/gitlab-lookup-issue
      :desc "GitLab Insert Issue Ref" "g c" #'my/gitlab-insert-issue-ref
      :desc "GitLab Refresh Issue" "g r" #'my/gitlab-refresh-issue
      :desc "GitLab Fetch MRs for Issue" "g f" #'my/gitlab-fetch-mr
      :desc "GitLab Merge Requests" "g m" #'my/gitlab-fetch-prs)

(defun my/gitlab-fetch-todos (&optional type-filter state-filter)
  "Fetch and display GitLab todos in a read-only buffer.
TYPE-FILTER can be: Issue, MergeRequest, Commit, Epic, Vulnerability, or Project.
STATE-FILTER can be: pending or done. If nil, shows pending todos.

Keybindings:
  d / RET - Toggle todo done/pending
  r / gr  - Refresh todos
  a       - Show all pending todos
  c       - Show completed todos
  i       - Show issue todos
  m       - Show merge request todos
  q       - Quit window"
  (interactive)
  (let* ((token (my/gitlab-get-token))
         (api-url (concat (format "%s/api/v4/todos?per_page=100" my/gitlab-url)
                         (when type-filter (format "&type=%s" type-filter))
                         (when state-filter (format "&state=%s" state-filter))))
         (url-request-extra-headers
          `(("PRIVATE-TOKEN" . ,token)))
         (url-request-method "GET"))

    (url-retrieve api-url
                  (lambda (status)
                    (if (plist-get status :error)
                        (message "Error fetching todos: %s" (plist-get status :error))
                      (goto-char url-http-end-of-headers)
                      (let* ((json-object-type 'hash-table)
                             (json-array-type 'list)
                             (json-key-type 'string)
                             (todos (json-read))
                             (buf (get-buffer-create "*GitLab Todos*")))

                        (with-current-buffer buf
                          (let ((inhibit-read-only t)
                                (filter-desc (cond
                                             ((and type-filter state-filter)
                                              (format " [%s, %s]" type-filter state-filter))
                                             (type-filter (format " [%s]" type-filter))
                                             (state-filter (format " [%s]" state-filter))
                                             (t ""))))
                            (erase-buffer)
                            (insert (propertize (format "GitLab Todos%s\n" filter-desc) 'face 'bold))
                            (insert (propertize (format "Total: %d\n" (length todos)) 'face 'font-lock-comment-face))
                            (insert (propertize "d/RET: toggle | r: refresh | a: all | c: completed | i: issues | m: MRs | q: quit\n\n" 'face 'font-lock-comment-face))

                            (if (zerop (length todos))
                                (insert "No todos! 🎉\n")
                              (dolist (todo todos)
                                (let* ((id (gethash "id" todo))
                                       (action (gethash "action_name" todo))
                                       (target-type (gethash "target_type" todo))
                                       (target (gethash "target" todo))
                                       (target-title (when target (gethash "title" target)))
                                       (target-url (when target (gethash "web_url" target)))
                                       (target-created-at (when target (gethash "created_at" target)))
                                       (project (gethash "project" todo))
                                       (project-name (when project (gethash "name" project)))
                                       (author (gethash "author" todo))
                                       (author-name (when author (gethash "name" author)))
                                       (state (gethash "state" todo))
                                       (entry-start (point)))

                                  ;; :: Insert todo entry
                                  (insert (propertize (format "• [%s] " state)
                                                     'face (if (string= state "pending") 'warning 'success)))
                                  (insert (propertize (format "%s" action) 'face 'bold))
                                  (when target-title
                                    (insert (format ": %s" target-title)))
                                  (insert "\n")

                                  (when project-name
                                    (insert (format "  Project: %s\n" project-name)))
                                  (when author-name
                                    (insert (format "  Author: %s\n" author-name)))
                                  (when target-created-at
                                    (insert (format "  Date: %s\n"
                                                   (format-time-string "%Y-%m-%d %H:%M"
                                                                      (date-to-time target-created-at)))))
                                  (when target-url
                                    (insert "  URL: ")
                                    (insert-text-button target-url
                                                       'action (lambda (_) (browse-url target-url))
                                                       'follow-link t
                                                       'help-echo "Click to open in browser")
                                    (insert "\n"))
                                  (insert "\n")

                                  ;; :: Add todo-id and todo-state properties to entire entry
                                  (put-text-property entry-start (point) 'todo-id id)
                                  (put-text-property entry-start (point) 'todo-state state))))

                            (goto-char (point-min))
                            (gitlab-todos-mode)
                            (setq my/gitlab-todos-type-filter type-filter)
                            (setq my/gitlab-todos-state-filter state-filter)))

                        (pop-to-buffer buf)
                        (message "Fetched %d todos" (length todos)))))
                  nil t)))


(defun my/gitlab-lookup-issue (issue-id)
  "Fetch GitLab issue and create a local org file with issue details.
Creates file at GITLAB_ISSUES_DIR/PROJECT_NAME#<ID> - <Title>.org"
  (interactive "sGitLab Issue ID: ")
  (my/gitlab-check-config)
  (let* ((token (my/gitlab-get-token))
         (project-id-encoded (url-hexify-string my/gitlab-project-id))
         (api-url (format "%s/api/v4/projects/%s/issues/%s"
                          my/gitlab-url
                          project-id-encoded
                          issue-id))
         (url-request-extra-headers
          `(("PRIVATE-TOKEN" . ,token)))
         (url-request-method "GET"))

    (url-retrieve api-url
                  (lambda (status)
                    (if (plist-get status :error)
                        (message "Error fetching issue: %s" (plist-get status :error))
                      (goto-char url-http-end-of-headers)
                      (let* ((json-object-type 'hash-table)
                             (json-array-type 'list)
                             (json-key-type 'string)
                             (json (json-read))
                             (title (gethash "title" json))
                             (description (or (gethash "description" json) ""))
                             (state (gethash "state" json))
                             (labels (gethash "labels" json))
                             (created-at (gethash "created_at" json))
                             (updated-at (gethash "updated_at" json))
                             (closed-at (gethash "closed_at" json))
                             (assignees (gethash "assignees" json))
                             (author (gethash "author" json))
                             (web-url (gethash "web_url" json))
                             (milestone (gethash "milestone" json))
                             ;; :: Sanitize title for filename
                             (safe-title (replace-regexp-in-string "[:/\\?*|<>]" "-" title))
                             (filename (format "%s#%s - %s.org" my/gitlab-project-name issue-id safe-title))
                             (filepath (expand-file-name filename my/gitlab-issues-dir)))

                        ;; :: Ensure directory exists
                        (make-directory (file-name-directory filepath) t)

                        ;; :: Convert markdown description to org using pandoc
                        (let ((org-description
                               (if (string-empty-p description)
                                   ""
                                 (with-temp-buffer
                                   (insert description)
                                   (shell-command-on-region
                                    (point-min) (point-max)
                                    "pandoc -f markdown -t org"
                                    (current-buffer) t)
                                   (buffer-string)))))

                          ;; :: Create org file content
                          (with-temp-file filepath
                            (insert (format "#+TITLE: %s#%s - %s\n" my/gitlab-project-name issue-id title))
                            (insert (format "#+DATE: %s\n\n" (format-time-string "%Y-%m-%d")))
                            (insert (format "* Issue Details\n\n"))
                            (insert (format "- *Status:* %s\n" state))
                            (insert (format "- *URL:* [[%s][GitLab Issue #%s]]\n" web-url issue-id))
                            (when author
                              (insert (format "- *Author:* %s\n" (gethash "name" author))))
                            (when labels
                              (insert (format "- *Labels:* %s\n"
                                            (mapconcat 'identity labels ", "))))
                            (when milestone
                              (insert (format "- *Milestone:* %s\n"
                                            (gethash "title" milestone))))
                            (when assignees
                              (insert (format "- *Assignees:* %s\n"
                                            (mapconcat (lambda (a) (gethash "name" a))
                                                      assignees ", "))))
                            (insert (format "- *Created:* %s\n"
                                          (format-time-string "%Y-%m-%d %H:%M"
                                                            (date-to-time created-at))))
                            (insert (format "- *Updated:* %s\n"
                                          (format-time-string "%Y-%m-%d %H:%M"
                                                            (date-to-time updated-at))))
                            (when closed-at
                              (insert (format "- *Closed:* %s\n"
                                            (format-time-string "%Y-%m-%d %H:%M"
                                                              (date-to-time closed-at)))))
                            (insert "\n* Description\n\n")
                            (insert org-description)
                            (insert "\n\n* Notes\n\n"))

                          ;; :: Open the file
                          (find-file filepath)
                          (message "Created issue file: %s" filename)))))
                  nil t)))

(defun my/gitlab-insert-issue-ref (issue-id)
  "Fetch GitLab issue ISSUE-ID and insert a short reference at point.
Inserts in the format: [PROJECT_NAME#<id>] <title>"
  (interactive "sGitLab Issue ID: ")
  (my/gitlab-check-config)
  (let* ((token (my/gitlab-get-token))
         (project-id-encoded (url-hexify-string my/gitlab-project-id))
         (api-url (format "%s/api/v4/projects/%s/issues/%s"
                          my/gitlab-url
                          project-id-encoded
                          issue-id))
         (url-request-extra-headers
          `(("PRIVATE-TOKEN" . ,token)))
         (url-request-method "GET")
         ;; :: Capture insertion point since url-retrieve is async
         (target-buffer (current-buffer))
         (target-marker (copy-marker (point) t)))

    (url-retrieve api-url
                  (lambda (status)
                    (if (plist-get status :error)
                        (message "Error fetching issue: %s" (plist-get status :error))
                      (goto-char url-http-end-of-headers)
                      (let* ((json-object-type 'hash-table)
                             (json-array-type 'list)
                             (json-key-type 'string)
                             (json (json-read))
                             (title (gethash "title" json))
                             (ref (format "[%s#%s] %s" my/gitlab-project-name issue-id title)))
                        (if (buffer-live-p target-buffer)
                            (with-current-buffer target-buffer
                              (save-excursion
                                (goto-char target-marker)
                                (insert ref))
                              (message "Inserted: %s" ref))
                          (message "Target buffer no longer live; ref was: %s" ref)))))
                  nil t)))

(defun my/gitlab-refresh-issue ()
  "Refresh the current GitLab issue org file with latest data from API.
Preserves the Notes section. Only works on files in GITLAB_ISSUES_DIR."
  (interactive)
  (my/gitlab-check-config)
  (let* ((current-file (buffer-file-name))
         (issues-dir my/gitlab-issues-dir)
         (filename (when current-file (file-name-nondirectory current-file))))

    ;; :: Check if we're in the issues directory
    (unless (and current-file
                 (string-prefix-p issues-dir (expand-file-name current-file)))
      (error "This command only works on files in %s" issues-dir))

    ;; :: Extract issue ID from filename
    (unless (string-match (format "^%s#\\([0-9]+\\)" my/gitlab-project-name) filename)
      (error "Filename must start with %s#<ID>" my/gitlab-project-name))

    (let* ((issue-id (match-string 1 filename))
           (token (my/gitlab-get-token))
           (project-id-encoded (url-hexify-string my/gitlab-project-id))
           (api-url (format "%s/api/v4/projects/%s/issues/%s"
                            my/gitlab-url
                            project-id-encoded
                            issue-id))
           (url-request-extra-headers
            `(("PRIVATE-TOKEN" . ,token)))
           (url-request-method "GET")
           ;; :: Preserve current Notes section
           (notes-content
            (save-excursion
              (goto-char (point-min))
              (if (re-search-forward "^\\* Notes\n+" nil t)
                  (buffer-substring-no-properties (point) (point-max))
                ""))))

      (url-retrieve api-url
                    (lambda (status)
                      (if (plist-get status :error)
                          (message "Error fetching issue: %s" (plist-get status :error))
                        (goto-char url-http-end-of-headers)
                        (let* ((json-object-type 'hash-table)
                               (json-array-type 'list)
                               (json-key-type 'string)
                               (json (json-read))
                               (title (gethash "title" json))
                               (description (or (gethash "description" json) ""))
                               (state (gethash "state" json))
                               (labels (gethash "labels" json))
                               (created-at (gethash "created_at" json))
                               (updated-at (gethash "updated_at" json))
                               (closed-at (gethash "closed_at" json))
                               (assignees (gethash "assignees" json))
                               (author (gethash "author" json))
                               (web-url (gethash "web_url" json))
                               (milestone (gethash "milestone" json)))

                          ;; :: Convert markdown description to org using pandoc
                          (let ((org-description
                                 (if (string-empty-p description)
                                     ""
                                   (with-temp-buffer
                                     (insert description)
                                     (shell-command-on-region
                                      (point-min) (point-max)
                                      "pandoc -f markdown -t org"
                                      (current-buffer) t)
                                     (buffer-string)))))

                            ;; :: Update the file content
                            (with-current-buffer (find-file-noselect current-file)
                              (erase-buffer)
                              (insert (format "#+TITLE: %s#%s - %s\n" my/gitlab-project-name issue-id title))
                              (insert (format "#+DATE: %s\n\n" (format-time-string "%Y-%m-%d")))
                              (insert (format "* Issue Details\n\n"))
                              (insert (format "- *Status:* %s\n" state))
                              (insert (format "- *URL:* [[%s][GitLab Issue #%s]]\n" web-url issue-id))
                              (when author
                                (insert (format "- *Author:* %s\n" (gethash "name" author))))
                              (when labels
                                (insert (format "- *Labels:* %s\n"
                                              (mapconcat 'identity labels ", "))))
                              (when milestone
                                (insert (format "- *Milestone:* %s\n"
                                              (gethash "title" milestone))))
                              (when assignees
                                (insert (format "- *Assignees:* %s\n"
                                              (mapconcat (lambda (a) (gethash "name" a))
                                                        assignees ", "))))
                              (insert (format "- *Created:* %s\n"
                                            (format-time-string "%Y-%m-%d %H:%M"
                                                              (date-to-time created-at))))
                              (insert (format "- *Updated:* %s\n"
                                            (format-time-string "%Y-%m-%d %H:%M"
                                                              (date-to-time updated-at))))
                              (when closed-at
                                (insert (format "- *Closed:* %s\n"
                                              (format-time-string "%Y-%m-%d %H:%M"
                                                                (date-to-time closed-at)))))
                              (insert "\n* Description\n\n")
                              (insert org-description)
                              (insert "\n\n* Notes\n\n")
                              (insert notes-content)
                              (save-buffer)
                              (message "Refreshed issue #%s - %s" issue-id title))))))
                    nil t))))

(defun my/gitlab-fetch-prs ()
  "Fetch and display GitLab MRs (wrapper for todos with MergeRequest filter)."
  (interactive)
  (my/gitlab-fetch-todos "MergeRequest" nil))

(defun my/gitlab-fetch-mr ()
  "Fetch linked Merge Requests for the current issue and add them to Notes section.
Only works on files in GITLAB_ISSUES_DIR."
  (interactive)
  (my/gitlab-check-config)
  (let* ((current-file (buffer-file-name))
         (issues-dir my/gitlab-issues-dir)
         (filename (when current-file (file-name-nondirectory current-file))))

    ;; :: Check if we're in the issues directory
    (unless (and current-file
                 (string-prefix-p issues-dir (expand-file-name current-file)))
      (error "This command only works on files in %s" issues-dir))

    ;; :: Extract issue ID from filename
    (unless (string-match (format "^%s#\\([0-9]+\\)" my/gitlab-project-name) filename)
      (error "Filename must start with %s#<ID>" my/gitlab-project-name))

    (let* ((issue-id (match-string 1 filename))
           (token (my/gitlab-get-token))
           (project-id-encoded (url-hexify-string my/gitlab-project-id))
           (api-url (format "%s/api/v4/projects/%s/issues/%s/related_merge_requests"
                            my/gitlab-url
                            project-id-encoded
                            issue-id))
           (url-request-extra-headers
            `(("PRIVATE-TOKEN" . ,token)))
           (url-request-method "GET"))

      (url-retrieve api-url
                    (lambda (status)
                      (if (plist-get status :error)
                          (message "Error fetching MRs: %s" (plist-get status :error))
                        (goto-char url-http-end-of-headers)
                        (let* ((json-object-type 'hash-table)
                               (json-array-type 'list)
                               (json-key-type 'string)
                               (mrs (json-read)))

                          (if (zerop (length mrs))
                              (message "No linked merge requests found for issue #%s" issue-id)
                            (with-current-buffer (find-file-noselect current-file)
                              ;; :: Find or create Notes section
                              (save-excursion
                                (goto-char (point-min))
                                (if (re-search-forward "^\\* Notes" nil t)
                                    (progn
                                      ;; :: Move past the heading and any whitespace
                                      (forward-line 1)
                                      (skip-chars-forward " \t\n")
                                      ;; :: Check if MRs section already exists
                                      (let ((notes-start (point)))
                                        (if (re-search-forward "^\\*\\* Linked Merge Requests\\n" nil t)
                                            ;; :: Delete existing MRs section
                                            (let ((mr-start (match-beginning 0)))
                                              (if (re-search-forward "^\\*\\*\\|^\\*[^*]" nil t)
                                                  (delete-region mr-start (match-beginning 0))
                                                (delete-region mr-start (point-max))))
                                          ;; :: Go back to notes start to insert new section
                                          (goto-char notes-start)))

                                      ;; :: Insert MRs section
                                      (insert "** Linked Merge Requests\n\n")
                                      (dolist (mr mrs)
                                        (let* ((mr-iid (gethash "iid" mr))
                                               (mr-title (gethash "title" mr))
                                               (mr-state (gethash "state" mr))
                                               (mr-url (gethash "web_url" mr))
                                               (mr-author (gethash "author" mr))
                                               (mr-author-name (when mr-author (gethash "name" mr-author)))
                                               (created-at (gethash "created_at" mr)))

                                          (insert (format "- [[%s][!%s - %s]]\n" mr-url mr-iid mr-title))
                                          (insert (format "  - State: %s\n" mr-state))
                                          (when mr-author-name
                                            (insert (format "  - Author: %s\n" mr-author-name)))
                                          (when created-at
                                            (insert (format "  - Created: %s\n"
                                                          (format-time-string "%Y-%m-%d %H:%M"
                                                                            (date-to-time created-at)))))
                                          (insert "\n")))
                                      (insert "\n")
                                      (save-buffer)
                                      (message "Added %d merge request(s) to Notes section" (length mrs))))
                                  (error "No Notes section found in current file")))))))
                    nil t))))

;; :: ============================================================
;; :: Merge Request Creation (via glab CLI)
;; :: ============================================================

(defvar my/gitlab-mr-template-file
  (expand-file-name "~/notes/templates/merge_request_template.md")
  "Path to the merge request description template.")

(defvar-local my/gitlab-mr--title nil
  "Title captured for the MR being composed in this buffer.")
(defvar-local my/gitlab-mr--target nil
  "Target branch captured for the MR being composed in this buffer.")
(defvar-local my/gitlab-mr--source nil
  "Source branch captured for the MR being composed in this buffer.")
(defvar-local my/gitlab-mr--draft nil
  "Whether the MR being composed in this buffer is a draft.")
(defvar-local my/gitlab-mr--directory nil
  "Repository directory the MR should be created from.")

(defun my/gitlab-mr--git (dir &rest args)
  "Run git with ARGS in DIR and return trimmed stdout, or nil on failure."
  (let ((default-directory dir))
    (with-temp-buffer
      (when (zerop (apply #'process-file "git" nil t nil args))
        (string-trim (buffer-string))))))

(defun my/gitlab-mr--current-branch (dir)
  "Return the current git branch in DIR."
  (my/gitlab-mr--git dir "rev-parse" "--abbrev-ref" "HEAD"))

(defun my/gitlab-mr--default-branch (dir)
  "Return the remote default branch in DIR, falling back to main/master."
  (let ((ref (my/gitlab-mr--git dir "symbolic-ref" "--short" "refs/remotes/origin/HEAD")))
    (cond
     (ref (replace-regexp-in-string "^origin/" "" ref))
     ((my/gitlab-mr--git dir "rev-parse" "--verify" "--quiet" "main") "main")
     (t "master"))))

(defun my/gitlab-mr--last-subject (dir)
  "Return the subject line of the latest commit in DIR."
  (my/gitlab-mr--git dir "log" "-1" "--pretty=%s"))

(defun my/gitlab-create-mr ()
  "Interactively create a GitLab merge request using glab and the MR template.
Prompts for title, target branch and draft status, then opens an editable
buffer pre-filled with `my/gitlab-mr-template-file'. Press \\[my/gitlab-mr-submit]
to create the MR or \\[my/gitlab-mr-cancel] to abort."
  (interactive)
  (unless (executable-find "glab")
    (error "glab CLI not found on PATH"))
  (let* ((dir (or (vc-root-dir)
                  (error "Not inside a version-controlled repository")))
         (source (or (my/gitlab-mr--current-branch dir)
                     (error "Could not determine current branch")))
         (default-branch (my/gitlab-mr--default-branch dir))
         (title (read-string "MR title: " (my/gitlab-mr--last-subject dir)))
         (target (read-string "Target branch: " default-branch))
         (draft (y-or-n-p "Mark as draft? "))
         (buf (get-buffer-create "*GitLab MR*")))
    (when (string-blank-p title)
      (error "MR title cannot be empty"))
    (with-current-buffer buf
      (erase-buffer)
      (if (file-readable-p my/gitlab-mr-template-file)
          (insert-file-contents my/gitlab-mr-template-file)
        (message "Template not found at %s; starting blank" my/gitlab-mr-template-file))
      (if (fboundp 'gfm-mode) (gfm-mode) (text-mode))
      (setq my/gitlab-mr--title title
            my/gitlab-mr--target target
            my/gitlab-mr--source source
            my/gitlab-mr--draft draft
            my/gitlab-mr--directory dir)
      (use-local-map (copy-keymap (current-local-map)))
      (local-set-key (kbd "C-c C-c") #'my/gitlab-mr-submit)
      (local-set-key (kbd "C-c C-k") #'my/gitlab-mr-cancel)
      (setq header-line-format
            (format " %s%s → %s   |   C-c C-c: create   C-c C-k: cancel"
                    (if draft "[DRAFT] " "") source target))
      (goto-char (point-min)))
    (pop-to-buffer buf)
    (message "Edit the MR description, then C-c C-c to create (C-c C-k to cancel)")))

(defun my/gitlab-mr-cancel ()
  "Cancel MR composition."
  (interactive)
  (when (yes-or-no-p "Discard this merge request? ")
    (kill-buffer (current-buffer))
    (message "MR creation cancelled")))

(defun my/gitlab-mr-submit ()
  "Submit the merge request composed in the current buffer via glab."
  (interactive)
  (let* ((title my/gitlab-mr--title)
         (target my/gitlab-mr--target)
         (source my/gitlab-mr--source)
         (draft my/gitlab-mr--draft)
         (dir my/gitlab-mr--directory)
         (description (buffer-substring-no-properties (point-min) (point-max)))
         (default-directory dir)
         (args (append
                (list "mr" "create"
                      "--source-branch" source
                      "--target-branch" target
                      "--title" title
                      "--description" description
                      "--no-editor"
                      "--yes")
                (when draft (list "--draft"))))
         (out-buf (get-buffer-create "*glab mr create*")))
    (with-current-buffer out-buf
      (let ((inhibit-read-only t)) (erase-buffer))
      (setq default-directory dir))
    (message "Creating merge request...")
    (make-process
     :name "glab-mr-create"
     :buffer out-buf
     :command (cons "glab" args)
     :sentinel
     (lambda (proc _event)
       (when (memq (process-status proc) '(exit signal))
         (with-current-buffer (process-buffer proc)
           (goto-char (point-max)))
         (if (zerop (process-exit-status proc))
             (let ((url (with-current-buffer out-buf
                          (when (re-search-backward "https?://[^ \n]+" nil t)
                            (match-string 0)))))
               (when (buffer-live-p (get-buffer "*GitLab MR*"))
                 (kill-buffer "*GitLab MR*"))
               (if url
                   (progn (kill-new url)
                          (message "MR created: %s (copied to kill-ring)" url))
                 (message "MR created successfully")))
           (progn
             (pop-to-buffer out-buf)
             (message "glab mr create failed (see *glab mr create*)"))))))))

;; :: Keybinding for MR creation
(map! :leader
      :prefix "o"
      :desc "GitLab Create MR" "g M" #'my/gitlab-create-mr)

(provide 'gitlab)
;;; gitlab.el ends here
