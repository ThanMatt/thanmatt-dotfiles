;;; gitlab/todos.el --- GitLab: todos buffer -*- lexical-binding: t; -*-

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
                      (let* ((todos (my/gitlab--read-json-body))
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

(defun my/gitlab-fetch-prs ()
  "Fetch and display GitLab MRs (wrapper for todos with MergeRequest filter)."
  (interactive)
  (my/gitlab-fetch-todos "MergeRequest" nil))

;;; todos.el ends here
