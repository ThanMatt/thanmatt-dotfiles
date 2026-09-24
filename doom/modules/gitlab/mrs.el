;;; gitlab/mrs.el --- GitLab: "My MRs" dashboard + single MR view -*- lexical-binding: t; -*-

;; :: ------------------------------------------------------------
;; :: Merge request dashboard
;; :: ------------------------------------------------------------

(defvar my/gitlab-mrs-buffer-name "*GitLab My MRs*"
  "Buffer name for the merge request dashboard.")

(defvar-local my/gitlab-mrs--approvals nil
  "Hash of MR key (see `my/gitlab-mrs--key') to its approvals payload.")

(defun my/gitlab-mrs--key (mr)
  "Return a stable key for MR, unique across projects on the same page."
  (format "%s!%s" (gethash "project_id" mr) (gethash "iid" mr)))

(defun my/gitlab-mrs--scope-label (scope)
  "Return a human label for SCOPE."
  (if (string= scope "assigned_to_me") "assigned to me" "created by me"))


(defun my/gitlab-mrs--status (mr)
  "Return (LABEL . FACE) describing the overall status of MR."
  (let ((state (gethash "state" mr))
        (draft (or (my/gitlab--truthy (gethash "draft" mr))
                   (my/gitlab--truthy (gethash "work_in_progress" mr))))
        (conflicts (my/gitlab--truthy (gethash "has_conflicts" mr))))
    (cond
     ((equal state "merged") (cons "merged" 'success))
     ((equal state "closed") (cons "closed" 'error))
     ((equal state "locked") (cons "locked" 'warning))
     (conflicts (cons "conflict" 'error))
     (draft (cons "draft" 'font-lock-comment-face))
     (t (cons "open" 'warning)))))

(defun my/gitlab-mrs--approvals-payload-p (data)
  "Return DATA when it looks like an approvals response rather than an error."
  (and (my/gitlab--has-key data "approved_by") data))

(defun my/gitlab-mrs--approval-cell (mr approvals)
  "Return (TEXT . FACE) for MR's approval count, from the APPROVALS hash.
Shows \"…\" while the per-MR approvals request is still in flight."
  (let ((data (and approvals (gethash (my/gitlab-mrs--key mr) approvals))))
    (if (null data)
        (cons "…" 'shadow)
      (let* ((count (length (gethash "approved_by" data)))
             (required (gethash "approvals_required" data))
             (text (if (and (numberp required) (> required 0))
                       (format "%d/%d" count required)
                     (format "%d" count))))
        (cons text (if (> count 0) 'success 'shadow))))))

(defun my/gitlab-mrs--threads-cell (mr)
  "Return (TEXT . FACE) summarising review activity on MR.
A trailing `!' means at least one thread is still unresolved."
  (let* ((notes (or (gethash "user_notes_count" mr) 0))
         (unresolved (and (my/gitlab--has-key mr "blocking_discussions_resolved")
                          (not (my/gitlab--truthy
                                (gethash "blocking_discussions_resolved" mr))))))
    (cond
     ((and (zerop notes) (not unresolved)) (cons "-" 'shadow))
     (unresolved (cons (format "%d!" notes) 'warning))
     (t (cons (format "%d" notes) 'default)))))


(defun my/gitlab-mrs--render (buf mrs page state scope sort approvals)
  "Draw MRS into BUF, recording the filter state for the shared commands."
  (with-current-buffer buf
    (let ((inhibit-read-only t)
          (line (line-number-at-pos)))
      (erase-buffer)
      (my/gitlab-dash--insert-header
       "GitLab Merge Requests" (my/gitlab-mrs--scope-label scope) state sort page
       (length mrs)
       (format "%-7s %-46s %-6s %-8s %-9s %-5s %s\n"
               "MR" "Title" "Appr" "Threads" "Status" "Age" "Project")
       my/gitlab-dash-help)
      (if (null mrs)
          (insert "\nNo merge requests found.\n")
        (dolist (mr mrs)
          (let* ((start (point))
                 (status (my/gitlab-mrs--status mr))
                 (appr (my/gitlab-mrs--approval-cell mr approvals))
                 (threads (my/gitlab-mrs--threads-cell mr)))
            (insert (propertize (format "%-7s " (format "!%s" (gethash "iid" mr)))
                                'face 'font-lock-constant-face))
            (insert (format "%s " (my/gitlab--truncate
                                   (my/gitlab--clean-title (gethash "title" mr)) 46)))
            (insert (propertize (format "%-6s " (car appr)) 'face (cdr appr)))
            (insert (propertize (format "%-8s " (car threads)) 'face (cdr threads)))
            (insert (propertize (format "%-9s " (car status)) 'face (cdr status)))
            (insert (format "%-5s " (my/gitlab--relative-time (gethash "created_at" mr))))
            (insert (propertize (my/gitlab--project-of mr) 'face 'font-lock-comment-face))
            (insert "\n")
            ;; :: The whole line carries the MR so point anywhere on it works
            (put-text-property start (point) 'gitlab-item mr))))
      (goto-char (point-min))
      (forward-line (1- line)))
    (unless (derived-mode-p 'gitlab-mrs-mode)
      (gitlab-mrs-mode))
    (setq my/gitlab-mrs--approvals approvals
          my/gitlab-dash--refetch #'my/gitlab-mrs--fetch)
    (my/gitlab-dash--finish page state scope sort mrs
                            '("opened" "merged" "closed" "all")
                            '("created_by_me" "assigned_to_me")
                            '("created_at" "updated_at"))))

(defun my/gitlab-mrs--fetch-approvals (mrs approvals buf page state scope sort)
  "Fetch approvals for each of MRS into APPROVALS, then re-render BUF.
The list renders immediately with a placeholder; this fills the column in
once every per-MR request has come back, so nothing blocks on N round trips."
  (let ((pending (length mrs)))
    (dolist (mr mrs)
      (my/gitlab--api-get-async
       (format "projects/%s/merge_requests/%s/approvals"
               (gethash "project_id" mr) (gethash "iid" mr))
       ""
       (lambda (data)
         (when (my/gitlab-mrs--approvals-payload-p data)
           (puthash (my/gitlab-mrs--key mr) data approvals))
         (setq pending (1- pending))
         (when (and (<= pending 0) (buffer-live-p buf))
           (my/gitlab-mrs--render buf mrs page state scope sort approvals)))))))

(defun my/gitlab-mrs--fetch (page state scope sort)
  "Fetch and display page PAGE of merge requests matching STATE, SCOPE and SORT."
  (message "Fetching merge requests (%s, %s, page %d)..."
           (my/gitlab-mrs--scope-label scope) state page)
  (my/gitlab--api-get-async
   "merge_requests"
   (format "scope=%s&state=%s&order_by=%s&sort=desc&per_page=%d&page=%d"
           scope state sort my/gitlab-dash-per-page page)
   (lambda (mrs)
     ;; :: A hash rather than a list: the approval callbacks land out of order
     (let ((approvals (make-hash-table :test 'equal))
           (buf (get-buffer-create my/gitlab-mrs-buffer-name)))
       (if (and mrs (hash-table-p mrs))
           (message "GitLab error: %s" (gethash "message" mrs))
         (my/gitlab-mrs--render buf mrs page state scope sort approvals)
         (pop-to-buffer buf)
         (message "Fetched %d merge request(s)" (length mrs))
         (when mrs
           (my/gitlab-mrs--fetch-approvals mrs approvals buf page state scope sort)))))))

;;;###autoload
(defun my/gitlab-my-merge-requests ()
  "Show your merge requests, newest opened first, in a dashboard buffer.

Each line shows the MR title, how many approvals it has, how many review
comments (with `!' when threads are still unresolved), its status and age.

Keybindings:
  RET / o - Open the MR in an org buffer
  b       - Open the MR in the browser
  y       - Copy the MR URL
  n / p   - Next / previous page
  s       - Cycle state filter (opened, merged, closed, all)
  t       - Toggle scope (created by me / assigned to me)
  S       - Toggle sort (newest / recently updated)
  r / gr  - Refresh
  q       - Quit window"
  (interactive)
  (my/gitlab-mrs--fetch 1 "opened" "created_by_me" "created_at"))

(defun my/gitlab-mrs-open-at-point ()
  "Open the merge request on the current line in an org buffer."
  (interactive)
  (let ((mr (my/gitlab-dash--at-point)))
    (my/gitlab-mr-view (gethash "project_id" mr) (gethash "iid" mr))))

(defvar gitlab-mrs-mode-map
  (my/gitlab-dash--bind (make-sparse-keymap) 'my/gitlab-mrs-open-at-point)
  "Keymap for the GitLab merge request dashboard.")

(define-derived-mode gitlab-mrs-mode special-mode "GitLab-MRs"
  "Major mode for the GitLab merge request dashboard.
\\{gitlab-mrs-mode-map}"
  (setq truncate-lines t))

(with-eval-after-load 'evil
  (evil-set-initial-state 'gitlab-mrs-mode 'normal)
  (my/gitlab-dash--evil-bind gitlab-mrs-mode-map 'my/gitlab-mrs-open-at-point))

;; :: ------------------------------------------------------------
;; :: Single MR view (throwaway org buffer)
;; :: ------------------------------------------------------------

(defvar-local my/gitlab-mr-view--url nil
  "Web URL of the merge request rendered in this buffer.")
(defvar-local my/gitlab-mr-view--project nil
  "Project ID of the merge request rendered in this buffer.")
(defvar-local my/gitlab-mr-view--iid nil
  "IID of the merge request rendered in this buffer.")

(defun my/gitlab-mr-view-browse ()
  "Open the merge request shown in this buffer in the browser."
  (interactive)
  (if my/gitlab-mr-view--url
      (browse-url my/gitlab-mr-view--url)
    (user-error "No merge request in this buffer")))

(defun my/gitlab-mr-view-copy-url ()
  "Copy the URL of the merge request shown in this buffer."
  (interactive)
  (if my/gitlab-mr-view--url
      (progn (kill-new my/gitlab-mr-view--url)
             (message "Copied: %s" my/gitlab-mr-view--url))
    (user-error "No merge request in this buffer")))

(defun my/gitlab-mr-view-refresh ()
  "Re-fetch the merge request shown in this buffer."
  (interactive)
  (if (and my/gitlab-mr-view--project my/gitlab-mr-view--iid)
      (my/gitlab-mr-view my/gitlab-mr-view--project my/gitlab-mr-view--iid)
    (user-error "No merge request in this buffer")))

(defun my/gitlab--names (objects)
  "Return a comma separated list of the `name' fields of OBJECTS."
  (when objects
    (mapconcat (lambda (o) (or (gethash "name" o) (gethash "username" o))) objects ", ")))

(defun my/gitlab-mr-view--insert-discussions (discussions)
  "Insert DISCUSSIONS as an org `Review Threads' section.
System notes (label changes, pushes) are dropped -- only human review
comments are worth reading here."
  (insert "\n* Review Threads\n\n")
  (let ((shown 0))
    (dolist (discussion discussions)
      (let* ((notes (seq-remove (lambda (n) (my/gitlab--truthy (gethash "system" n)))
                                (or (gethash "notes" discussion) nil)))
             (first (car notes)))
        (when first
          (setq shown (1+ shown))
          (let* ((resolvable (my/gitlab--truthy (gethash "resolvable" first)))
                 (resolved (my/gitlab--truthy (gethash "resolved" first)))
                 (position (gethash "position" first))
                 (path (and position (or (gethash "new_path" position)
                                         (gethash "old_path" position))))
                 (line (and position (or (gethash "new_line" position)
                                         (gethash "old_line" position))))
                 (tag (cond ((and resolvable resolved) "RESOLVED")
                            (resolvable "UNRESOLVED")
                            (t "COMMENT"))))
            (insert (format "** %s%s\n" tag
                            (if path (format " — %s%s" path
                                             (if line (format ":%s" line) ""))
                              "")))
            (dolist (note notes)
              (let ((author (gethash "author" note)))
                (insert (format "- *%s* — %s\n"
                                (if author (gethash "name" author) "unknown")
                                (format-time-string
                                 "%Y-%m-%d %H:%M"
                                 (date-to-time (gethash "created_at" note))))))
              (insert (my/gitlab--indent-block
                       (string-trim (or (gethash "body" note) "")) "  "))
              (insert "\n"))
            (insert "\n")))))
    (when (zerop shown)
      (insert "No review comments yet.\n"))))

(defun my/gitlab-mr-view--render (mr approvals discussions)
  "Render MR (plus APPROVALS and DISCUSSIONS) into a throwaway org buffer."
  (let* ((iid (gethash "iid" mr))
         (project (my/gitlab--project-of mr))
         (web-url (gethash "web_url" mr))
         (status (my/gitlab-mrs--status mr))
         (pipeline (gethash "head_pipeline" mr))
         (approved (and approvals (gethash "approved_by" approvals)))
         (buf (get-buffer-create (format "*GitLab MR !%s*" iid))))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "#+TITLE: !%s - %s\n" iid
                        (my/gitlab--clean-title (gethash "title" mr))))
        (insert (format "#+DATE: %s\n\n" (format-time-string "%Y-%m-%d")))
        (insert "* Merge Request\n\n")
        (insert (format "- *Status:* %s\n" (car status)))
        (insert (format "- *URL:* [[%s][GitLab MR !%s]]\n" web-url iid))
        (unless (string-empty-p project)
          (insert (format "- *Project:* %s\n" project)))
        (when-let* ((author (gethash "author" mr)))
          (insert (format "- *Author:* %s\n" (gethash "name" author))))
        (insert (format "- *Branches:* %s → %s\n"
                        (gethash "source_branch" mr) (gethash "target_branch" mr)))
        (insert (format "- *Approvals:* %d%s%s\n"
                        (length approved)
                        (let ((required (and approvals (gethash "approvals_required" approvals))))
                          (if (and (numberp required) (> required 0))
                              (format "/%d" required) ""))
                        (if approved
                            (format " — %s" (my/gitlab--names
                                             (mapcar (lambda (a) (gethash "user" a)) approved)))
                          "")))
        (when-let* ((reviewers (my/gitlab--names (gethash "reviewers" mr))))
          (insert (format "- *Reviewers:* %s\n" reviewers)))
        (when-let* ((assignees (my/gitlab--names (gethash "assignees" mr))))
          (insert (format "- *Assignees:* %s\n" assignees)))
        (when-let* ((labels (gethash "labels" mr)))
          (insert (format "- *Labels:* %s\n" (mapconcat #'identity labels ", "))))
        (when pipeline
          (insert (format "- *Pipeline:* %s\n" (gethash "status" pipeline))))
        (when-let* ((changes (gethash "changes_count" mr)))
          (insert (format "- *Changes:* %s file(s)\n" changes)))
        (insert (format "- *Comments:* %s%s\n"
                        (or (gethash "user_notes_count" mr) 0)
                        (if (and (my/gitlab--has-key mr "blocking_discussions_resolved")
                                 (not (my/gitlab--truthy
                                       (gethash "blocking_discussions_resolved" mr))))
                            " (unresolved threads)" "")))
        (when (my/gitlab--truthy (gethash "has_conflicts" mr))
          (insert "- *Conflicts:* yes\n"))
        (insert (format "- *Created:* %s\n"
                        (format-time-string "%Y-%m-%d %H:%M"
                                            (date-to-time (gethash "created_at" mr)))))
        (insert (format "- *Updated:* %s\n"
                        (format-time-string "%Y-%m-%d %H:%M"
                                            (date-to-time (gethash "updated_at" mr)))))
        (when-let* ((merged-at (gethash "merged_at" mr)))
          (insert (format "- *Merged:* %s\n"
                          (format-time-string "%Y-%m-%d %H:%M" (date-to-time merged-at)))))
        (when-let* ((closed-at (gethash "closed_at" mr)))
          (insert (format "- *Closed:* %s\n"
                          (format-time-string "%Y-%m-%d %H:%M" (date-to-time closed-at)))))
        (insert "\n* Description\n\n")
        (insert (my/gitlab--md-to-org (gethash "description" mr)))
        (insert "\n")
        (my/gitlab-mr-view--insert-discussions discussions)
        (goto-char (point-min)))
      (org-mode)
      (setq my/gitlab-mr-view--url web-url
            my/gitlab-mr-view--project (gethash "project_id" mr)
            my/gitlab-mr-view--iid iid)
      (setq buffer-read-only t)
      (setq header-line-format
            (format " !%s  %s   |   C-c C-b: browser   C-c C-y: copy URL   C-c C-r: refresh   q: quit"
                    iid (car status)))
      ;; :: org-mode is already on, so this copies its map without needing it loaded
      (use-local-map (copy-keymap (current-local-map)))
      (local-set-key (kbd "C-c C-b") #'my/gitlab-mr-view-browse)
      (local-set-key (kbd "C-c C-y") #'my/gitlab-mr-view-copy-url)
      (local-set-key (kbd "C-c C-r") #'my/gitlab-mr-view-refresh)
      (local-set-key (kbd "q") #'quit-window)
      ;; :: Evil normal state shadows the local map for q/b/y, so bind there too
      (when (fboundp 'evil-local-set-key)
        (evil-local-set-key 'normal (kbd "q") #'quit-window)
        (evil-local-set-key 'normal (kbd "gb") #'my/gitlab-mr-view-browse)
        (evil-local-set-key 'normal (kbd "gy") #'my/gitlab-mr-view-copy-url)
        (evil-local-set-key 'normal (kbd "gr") #'my/gitlab-mr-view-refresh)))
    (pop-to-buffer buf)))

(defun my/gitlab-mr-view (project-id iid)
  "Open merge request IID of PROJECT-ID in a throwaway org buffer.
Fetches the MR, its approvals and its discussions, then renders all three
into one read-only org buffer.  C-c C-b (or `gb') opens it in the browser."
  (interactive "sProject ID: \nsMR IID: ")
  (message "Fetching MR !%s..." iid)
  (my/gitlab--api-get-async
   (format "projects/%s/merge_requests/%s" project-id iid) ""
   (lambda (mr)
     (if (or (null mr) (null (gethash "iid" mr)))
         (message "Could not fetch MR !%s%s" iid
                  (if (and mr (gethash "message" mr))
                      (format ": %s" (gethash "message" mr)) ""))
       (my/gitlab--api-get-async
        (format "projects/%s/merge_requests/%s/approvals" project-id iid) ""
        (lambda (approvals)
          (my/gitlab--api-get-async
           (format "projects/%s/merge_requests/%s/discussions" project-id iid)
           "per_page=100"
           (lambda (discussions)
             (my/gitlab-mr-view--render
              mr
              (my/gitlab-mrs--approvals-payload-p approvals)
              (and (listp discussions) discussions))
             (message "Opened MR !%s" iid)))))))))

;;; mrs.el ends here
