;;; gitlab/issues-dash.el --- GitLab: assigned issues dashboard -*- lexical-binding: t; -*-

;; :: ------------------------------------------------------------
;; :: Assigned issue dashboard
;; :: ------------------------------------------------------------
;;
;; :: NOTE on ordering: GitLab exposes no "assigned to me at" timestamp, so
;; :: there is no way to sort by when a ticket landed on you.  `updated_at' is
;; :: the closest proxy -- assigning an issue bumps it, so fresh assignments
;; :: surface at the top -- and it is the default here.  `S' switches to
;; :: `created_at' (newest ticket) when that is what you actually want.

(defvar my/gitlab-issues-buffer-name "*GitLab My Issues*"
  "Buffer name for the assigned issue dashboard.")

(defun my/gitlab-issues--scope-label (scope)
  "Return a human label for SCOPE."
  (if (string= scope "created_by_me") "created by me" "assigned to me"))

(defun my/gitlab-issues--state-cell (issue)
  "Return (TEXT . FACE) for ISSUE's open/closed state."
  (if (equal (gethash "state" issue) "closed")
      (cons "closed" 'success)
    (cons "open" 'warning)))

(defun my/gitlab-issues--priority-face (priority)
  "Return a face matching the PRIORITY scoped-label value."
  (cond
   ((null priority) 'shadow)
   ((member priority '("urgent" "critical" "high")) 'error)
   ((equal priority "medium") 'warning)
   (t 'shadow)))


(defun my/gitlab-issues--render (buf issues page state scope sort)
  "Draw ISSUES into BUF, recording the filter state for the shared commands."
  (with-current-buffer buf
    (let ((inhibit-read-only t)
          (line (line-number-at-pos)))
      (erase-buffer)
      (my/gitlab-dash--insert-header
       "GitLab Issues" (my/gitlab-issues--scope-label scope) state sort page
       (length issues)
       (format "%-7s %-42s %-7s %-16s %-7s %-11s %-4s %s\n"
               "Issue" "Title" "State" "Stage" "Prio" "Milestone" "Cmt" "Age")
       my/gitlab-dash-help)
      (if (null issues)
          (insert "\nNo issues found.\n")
        (dolist (issue issues)
          (let* ((start (point))
                 (labels (gethash "labels" issue))
                 (st (my/gitlab-issues--state-cell issue))
                 (stage (my/gitlab--scoped-label labels "stage"))
                 (priority (my/gitlab--scoped-label labels "priority"))
                 (milestone (gethash "milestone" issue))
                 (notes (or (gethash "user_notes_count" issue) 0)))
            (insert (propertize (format "%-7s " (format "#%s" (gethash "iid" issue)))
                                'face 'font-lock-constant-face))
            (insert (format "%s " (my/gitlab--truncate (gethash "title" issue) 42)))
            (insert (propertize (format "%-7s " (car st)) 'face (cdr st)))
            (insert (propertize (format "%-16s " (my/gitlab--truncate (or stage "-") 16))
                                'face (if stage 'font-lock-type-face 'shadow)))
            (insert (propertize (format "%-7s " (my/gitlab--truncate (or priority "-") 7))
                                'face (my/gitlab-issues--priority-face priority)))
            (insert (propertize
                     (format "%-11s " (my/gitlab--truncate
                                       (if milestone (gethash "title" milestone) "-") 11))
                     'face (if milestone 'default 'shadow)))
            (insert (propertize (format "%-4s " (if (zerop notes) "-" (number-to-string notes)))
                                'face (if (zerop notes) 'shadow 'default)))
            ;; :: Age tracks whichever field the list is ordered by, so the
            ;; :: column always explains the row's position in the list
            (insert (my/gitlab--relative-time (gethash sort issue)))
            (insert "\n")
            (put-text-property start (point) 'gitlab-item issue))))
      (goto-char (point-min))
      (forward-line (1- line)))
    (unless (derived-mode-p 'gitlab-issues-mode)
      (gitlab-issues-mode))
    (setq my/gitlab-dash--refetch #'my/gitlab-issues--fetch)
    (my/gitlab-dash--finish page state scope sort issues
                            '("opened" "closed" "all")
                            '("assigned_to_me" "created_by_me")
                            '("updated_at" "created_at"))))

(defun my/gitlab-issues--fetch (page state scope sort)
  "Fetch and display page PAGE of issues matching STATE, SCOPE and SORT."
  (message "Fetching issues (%s, %s, page %d)..."
           (my/gitlab-issues--scope-label scope) state page)
  (my/gitlab--api-get-async
   "issues"
   (format "scope=%s&state=%s&order_by=%s&sort=desc&per_page=%d&page=%d"
           scope state sort my/gitlab-dash-per-page page)
   (lambda (issues)
     (let ((buf (get-buffer-create my/gitlab-issues-buffer-name)))
       (if (and issues (hash-table-p issues))
           (message "GitLab error: %s" (gethash "message" issues))
         (my/gitlab-issues--render buf issues page state scope sort)
         (pop-to-buffer buf)
         (message "Fetched %d issue(s)" (length issues)))))))

;;;###autoload
(defun my/gitlab-my-issues ()
  "Show the issues assigned to you, most recently touched first.

Ordered by `updated_at' because GitLab exposes no assignment timestamp --
assigning a ticket bumps that field, so new assignments rise to the top.
Press `S' to order by creation date instead.

Each line shows the ticket title, open/closed state, its `stage::' and
`priority::' scoped labels, milestone, comment count and age.

RET opens the ticket through the usual local-org-file flow (the same file
`my/gitlab-lookup-issue' uses, Notes section preserved) when it belongs to
`my/gitlab-project-name'; issues from other projects open in the browser.

Keybindings:
  RET / o - Open the ticket's local org file
  b       - Open the ticket in the browser
  y       - Copy the ticket URL
  n / p   - Next / previous page
  s       - Cycle state filter (opened, closed, all)
  t       - Toggle scope (assigned to me / created by me)
  S       - Toggle sort (recently updated / newest)
  r / gr  - Refresh
  q       - Quit window"
  (interactive)
  (my/gitlab-issues--fetch 1 "opened" "assigned_to_me" "updated_at"))

(defun my/gitlab-issues-open-at-point ()
  "Open the issue on the current line.
Reuses the local org file when the issue belongs to the configured
project, so the Notes section survives; otherwise falls back to the
browser, since the local filenames are keyed to one project."
  (interactive)
  (let* ((issue (my/gitlab-dash--at-point))
         (iid (number-to-string (gethash "iid" issue))))
    (if (my/gitlab--own-project-p (gethash "project_id" issue))
        (my/gitlab--save-issue-object-and-open iid issue)
      (message "Issue #%s is in %s, not %s -- opening in the browser"
               iid (my/gitlab--project-of issue) my/gitlab-project-name)
      (browse-url (gethash "web_url" issue)))))

(defvar gitlab-issues-mode-map
  (my/gitlab-dash--bind (make-sparse-keymap) 'my/gitlab-issues-open-at-point)
  "Keymap for the GitLab assigned issue dashboard.")

(define-derived-mode gitlab-issues-mode special-mode "GitLab-Issues"
  "Major mode for the GitLab assigned issue dashboard.
\\{gitlab-issues-mode-map}"
  (setq truncate-lines t))

(with-eval-after-load 'evil
  (evil-set-initial-state 'gitlab-issues-mode 'normal)
  (my/gitlab-dash--evil-bind gitlab-issues-mode-map 'my/gitlab-issues-open-at-point))

;;; issues-dash.el ends here
