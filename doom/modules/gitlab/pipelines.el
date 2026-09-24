;;; gitlab/pipelines.el --- GitLab: pipelines dashboard + pipeline watch -*- lexical-binding: t; -*-

;; :: ------------------------------------------------------------
;; :: Pipelines dashboard (one buffer per project) + pipeline watch
;; :: ------------------------------------------------------------
;;
;; :: `my/gitlab-pipelines' (SPC o g P) asks which project -- any project you
;; :: are a member of, most recently active first -- and lists its latest
;; :: pipelines one per line.  Each project gets its own buffer, so several
;; :: can stay open side by side.  RET, `o' and a mouse click open the
;; :: pipeline in the browser; `y' copies its URL.
;; ::
;; :: `w' watches the pipeline on the current line: a TODO heading with no
;; :: SCHEDULED time goes into the active vault's reminders.org (so `appt'
;; :: ignores it), and a timer polls GitLab every
;; :: `my/gitlab-pipelines-poll-interval' seconds through the same async
;; :: `url-retrieve' wrapper the dashboards use -- the wait happens in a
;; :: process filter, only the small callback runs on the main thread.  Once
;; :: the pipeline reaches a terminal status the heading flips to DONE, a
;; :: desktop notification fires via reminders.el, and the timer cancels
;; :: itself when nothing is left to watch.  `w' again unwatches (the heading
;; :: is marked DONE with `:GITLAB_STATUS: unwatched'); marking it DONE by
;; :: hand in reminders.org has the same effect.
;; ::
;; :: Limits: only the ACTIVE vault's reminders.org is polled (switching
;; :: vaults pauses watches in the one you left); the first poll after a cold
;; :: start may prompt for the GPG passphrase once, exactly like the first
;; :: manual GitLab command does; and a watch whose pipeline was deleted on
;; :: GitLab keeps polling until you mark its heading DONE by hand.

(defvar my/gitlab--projects-cache nil
  "Projects you are a member of, most recently active first.
Filled by `my/gitlab--fetch-projects'; `C-u' on `my/gitlab-pipelines'
refreshes it.")

(defvar my/gitlab-projects-max-pages 5
  "Safety cap on how many 100-project pages `my/gitlab--fetch-projects' walks.")

(defvar my/gitlab-pipelines-poll-interval 180
  "Seconds between polls of watched pipelines.")

(defconst my/gitlab-pipelines-terminal-statuses
  '("success" "failed" "canceled" "skipped" "manual")
  "Pipeline statuses that end a watch.
`manual' means the pipeline is blocked on a manual job -- it will not move
without you, so it counts as \"needs attention\" rather than \"still running\".")

(defvar my/gitlab--username nil
  "Your GitLab username, fetched once for the `mine' pipeline scope.")

(defvar my/gitlab-pipelines--poll-timer nil
  "Repeating timer behind the pipeline watches, or nil when nothing is watched.")

(defvar-local my/gitlab-pipelines--project nil
  "Project object (hash-table) this pipeline dashboard shows.")

(defvar-local my/gitlab-pipelines--details nil
  "Hash of pipeline id to its detail payload (duration, user).
Kept across refreshes: a finished pipeline's details never change, so only
the ones still moving are fetched again.")

;; :: Project picker

(defun my/gitlab--fetch-projects ()
  "Fetch every project you are a member of into `my/gitlab--projects-cache'.
Synchronous: the picker needs the whole list before it can prompt."
  (message "Fetching your GitLab projects...")
  (let ((page 1) (acc nil) (more t))
    (while (and more (<= page my/gitlab-projects-max-pages))
      (let ((batch (my/gitlab--api-get-sync
                    "projects"
                    (format "membership=true&simple=true&order_by=last_activity_at&sort=desc&per_page=100&page=%d"
                            page))))
        (when (hash-table-p batch)
          (error "GitLab error: %s" (gethash "message" batch)))
        (setq acc (append acc batch)
              more (= (length batch) 100)
              page (1+ page))))
    (message "Fetched %d project(s)" (length acc))
    (setq my/gitlab--projects-cache acc)))

(defun my/gitlab--read-project (&optional refresh)
  "Prompt for one of your projects and return its object (a hash-table).
Uses the cached list unless REFRESH is non-nil or nothing is cached yet.
The project `my/gitlab-project-id' names is offered as the default."
  (when (or refresh (null my/gitlab--projects-cache))
    (my/gitlab--fetch-projects))
  (unless my/gitlab--projects-cache
    (user-error "No GitLab projects found for this token"))
  (let* ((candidates (mapcar (lambda (p) (cons (gethash "path_with_namespace" p) p))
                             my/gitlab--projects-cache))
         (default (car (seq-find (lambda (c) (my/gitlab--own-project-p (gethash "id" (cdr c))))
                                 candidates)))
         (choice (completing-read
                  (format "Pipelines for project%s: "
                          (if default (format " (default %s)" default) ""))
                  (my/gitlab--completion-table candidates) nil t nil nil default)))
    (or (cdr (assoc choice candidates))
        (user-error "No project selected"))))

(defun my/gitlab--username ()
  "Return your GitLab username, fetching it on first use."
  (or my/gitlab--username
      (let ((me (my/gitlab--api-get-sync "user" "")))
        (setq my/gitlab--username (and (hash-table-p me) (gethash "username" me)))
        (or my/gitlab--username
            (error "Could not resolve your GitLab username")))))

;; :: Cells

(defun my/gitlab-pipelines--terminal-p (status)
  "Return non-nil when STATUS means the pipeline will not change any more."
  (member status my/gitlab-pipelines-terminal-statuses))

(defun my/gitlab-pipelines--buffer-name (project)
  "Return the dashboard buffer name for PROJECT."
  (format "*GitLab Pipelines: %s*" (gethash "path_with_namespace" project)))

(defun my/gitlab-pipelines--status-cell (status)
  "Return (TEXT . FACE) for the pipeline STATUS."
  (cons (or status "?")
        (pcase status
          ("success" 'success)
          ("failed" 'error)
          ("running" 'warning)
          ("manual" 'font-lock-type-face)
          (_ 'shadow))))

(defun my/gitlab-pipelines--duration-cell (pipeline details)
  "Return (TEXT . FACE) for PIPELINE's duration from the DETAILS hash.
Shows \"…\" while the detail request is still in flight, and \"~AGE\" --
time since the pipeline was created -- while it is still running, since
GitLab only reports `duration' once it has finished."
  (let ((data (and details (gethash (gethash "id" pipeline) details))))
    (cond
     ((null data) (cons "…" 'shadow))
     ((numberp (gethash "duration" data))
      (let ((secs (round (gethash "duration" data))))
        (cons (if (>= secs 3600)
                  (format "%dh%02dm" (/ secs 3600) (/ (% secs 3600) 60))
                (format "%d:%02d" (/ secs 60) (% secs 60)))
              'default)))
     ((member (gethash "status" pipeline) '("running" "pending"))
      (cons (concat "~" (my/gitlab--relative-time (gethash "created_at" pipeline)))
            'warning))
     (t (cons "-" 'shadow)))))

(defun my/gitlab-pipelines--ref-label (ref)
  "Return REF for display, collapsing MR pipeline refs to `!IID'."
  (if (and ref (string-match "\\`refs/merge-requests/\\([0-9]+\\)/\\(head\\|merge\\)\\'" ref))
      (format "!%s" (match-string 1 ref))
    (or ref "")))

(defun my/gitlab-pipelines--source-label (source)
  "Return a short label for what triggered a pipeline (SOURCE)."
  (pcase source
    ("merge_request_event" "MR")
    ("parent_pipeline" "parent")
    ("external_pull_request_event" "ext PR")
    (_ (or source "-"))))

(defun my/gitlab-pipelines--user-cell (pipeline details)
  "Return (TEXT . FACE) naming who triggered PIPELINE, from the DETAILS hash."
  (let* ((data (and details (gethash (gethash "id" pipeline) details)))
         (user (and data (gethash "user" data))))
    (cond
     ((null data) (cons "…" 'shadow))
     ((hash-table-p user) (cons (or (gethash "username" user) "-") 'default))
     (t (cons "-" 'shadow)))))

(defun my/gitlab-pipelines--short-sha (sha)
  "Return the first 8 characters of SHA."
  (let ((sha (or sha "")))
    (substring sha 0 (min 8 (length sha)))))

(defun my/gitlab-pipelines--watched-ids (project-id)
  "Return the ids (strings) of PROJECT-ID's pipelines still being watched."
  (let ((project-id (format "%s" project-id)))
    (delq nil
          (mapcar (lambda (w)
                    (and (equal (plist-get w :project) project-id)
                         (plist-get w :pipeline)))
                  (my/gitlab-pipelines--watches)))))

;; :: Render + fetch

(defun my/gitlab-pipelines--render (buf project pipelines page state scope sort details)
  "Draw PIPELINES of PROJECT into BUF, recording the filter state."
  (with-current-buffer buf
    (let ((inhibit-read-only t)
          (line (line-number-at-pos))
          (watched (my/gitlab-pipelines--watched-ids (gethash "id" project)))
          ;; :: Age tracks the sort field, so the column explains the row's position
          (age-field (if (equal sort "updated_at") "updated_at" "created_at")))
      (erase-buffer)
      (my/gitlab-dash--insert-header
       (format "GitLab Pipelines — %s" (gethash "path_with_namespace" project))
       (if (equal scope "mine") "mine" "everyone") state sort page
       (length pipelines)
       (format "%-12s %-9s %-28s %-10s %-8s %-7s %-12s %-5s %s\n"
               "ID" "Status" "Ref" "Source" "SHA" "Dur" "By" "Age" "W")
       (concat my/gitlab-dash-help "  w: watch/unwatch"))
      (if (null pipelines)
          (insert "\nNo pipelines found.\n")
        (dolist (pl pipelines)
          (let* ((start (point))
                 (status (my/gitlab-pipelines--status-cell (gethash "status" pl)))
                 (dur (my/gitlab-pipelines--duration-cell pl details))
                 (by (my/gitlab-pipelines--user-cell pl details))
                 (watched-p (member (format "%s" (gethash "id" pl)) watched)))
            (insert (propertize (format "%-12s " (format "#%s" (gethash "id" pl)))
                                'face 'font-lock-constant-face))
            (insert (propertize (format "%s " (my/gitlab--truncate (car status) 9))
                                'face (cdr status)))
            (insert (format "%s " (my/gitlab--truncate
                                   (my/gitlab-pipelines--ref-label (gethash "ref" pl)) 28)))
            (insert (propertize (format "%s " (my/gitlab--truncate
                                               (my/gitlab-pipelines--source-label
                                                (gethash "source" pl)) 10))
                                'face 'font-lock-comment-face))
            (insert (propertize (format "%-8s " (my/gitlab-pipelines--short-sha (gethash "sha" pl)))
                                'face 'shadow))
            (insert (propertize (format "%-7s " (car dur)) 'face (cdr dur)))
            (insert (propertize (format "%s " (my/gitlab--truncate (car by) 12)) 'face (cdr by)))
            (insert (format "%-5s " (my/gitlab--relative-time (gethash age-field pl))))
            (insert (propertize (if watched-p "●" "") 'face 'warning))
            (insert "\n")
            ;; :: The whole line carries the pipeline so point anywhere on it works
            (put-text-property start (point) 'gitlab-item pl))))
      (goto-char (point-min))
      (forward-line (1- line)))
    (unless (derived-mode-p 'gitlab-pipelines-mode)
      (gitlab-pipelines-mode))
    (setq my/gitlab-pipelines--project project
          my/gitlab-pipelines--details details
          ;; :: Closes over PROJECT so the shared n/p/s/t/S/r keys need no changes
          my/gitlab-dash--refetch
          (lambda (page state scope sort)
            (my/gitlab-pipelines--fetch project page state scope sort)))
    (my/gitlab-dash--finish page state scope sort pipelines
                            '("all" "running" "pending" "success" "failed" "canceled")
                            '("all" "mine")
                            '("id" "updated_at"))))

(defun my/gitlab-pipelines--fetch-details (buf project pipelines details page state scope sort)
  "Fill DETAILS for the PIPELINES that still need it, then re-render BUF once.
A pipeline whose cached details already show a terminal status is skipped:
its duration and trigger user cannot change, so a refresh only costs one
request per pipeline that is still moving.  The list renders immediately
with a placeholder, as the MR dashboard does for approvals."
  (let* ((wanted (seq-remove
                  (lambda (pl)
                    (let ((cached (gethash (gethash "id" pl) details)))
                      (and cached
                           (my/gitlab-pipelines--terminal-p (gethash "status" cached)))))
                  pipelines))
         (pending (length wanted)))
    (dolist (pl wanted)
      (my/gitlab--api-get-async
       (format "projects/%s/pipelines/%s" (gethash "id" project) (gethash "id" pl))
       ""
       (lambda (data)
         (when (my/gitlab--has-key data "id")
           (puthash (gethash "id" pl) data details))
         (setq pending (1- pending))
         ;; :: Only redraw if the buffer still shows this very listing -- a
         ;; :: filter change in the meantime must not be clobbered
         (when (and (<= pending 0)
                    (buffer-live-p buf)
                    (eq (buffer-local-value 'my/gitlab-dash--items buf) pipelines))
           (my/gitlab-pipelines--render buf project pipelines page state scope sort details)))))))

(defun my/gitlab-pipelines--query (page state scope sort)
  "Build the query string for page PAGE of pipelines matching STATE, SCOPE and SORT."
  (concat (format "order_by=%s&sort=desc&per_page=%d&page=%d"
                  sort my/gitlab-dash-per-page page)
          (unless (equal state "all") (format "&status=%s" state))
          (when (equal scope "mine")
            (format "&username=%s" (url-hexify-string (my/gitlab--username))))))

(defun my/gitlab-pipelines--fetch (project page state scope sort)
  "Fetch and display page PAGE of PROJECT's pipelines matching STATE, SCOPE and SORT."
  (let ((path (gethash "path_with_namespace" project))
        (query (my/gitlab-pipelines--query page state scope sort)))
    (message "Fetching pipelines for %s (%s, page %d)..." path state page)
    (my/gitlab--api-get-async
     (format "projects/%s/pipelines" (gethash "id" project))
     query
     (lambda (pipelines)
       (let* ((buf (get-buffer-create (my/gitlab-pipelines--buffer-name project)))
              ;; :: Reuse the buffer's detail cache so finished rows stay filled
              (details (or (buffer-local-value 'my/gitlab-pipelines--details buf)
                           (make-hash-table :test 'equal))))
         (if (and pipelines (hash-table-p pipelines))
             (message "GitLab error: %s" (gethash "message" pipelines))
           (my/gitlab-pipelines--render buf project pipelines page state scope sort details)
           (pop-to-buffer buf)
           (message "Fetched %d pipeline(s) for %s" (length pipelines) path)
           (when pipelines
             (my/gitlab-pipelines--fetch-details
              buf project pipelines details page state scope sort))))))))

;;;###autoload
(defun my/gitlab-pipelines (&optional refresh)
  "Show the latest pipelines of one of your projects in a dashboard buffer.

Prompts for the project (every project you are a member of, most recently
active first, defaulting to `my/gitlab-project-name').  With a prefix
argument REFRESH the project list is fetched again instead of reusing the
cached one.

Each line shows the pipeline id, status, ref, what triggered it, the short
SHA, its duration and trigger user (filled in a moment after the list),
age, and a `●' when the pipeline is being watched.

Keybindings:
  RET / o / click - Open the pipeline in the browser
  b       - Open the pipeline in the browser
  y       - Copy the pipeline URL
  w       - Watch / unwatch: reminder in reminders.org + notification when it ends
  n / p   - Next / previous page
  s       - Cycle status filter (all, running, pending, success, failed, canceled)
  t       - Toggle scope (everyone / mine)
  S       - Toggle sort (newest / recently updated)
  r / gr  - Refresh
  q       - Quit window"
  (interactive "P")
  (let ((project (my/gitlab--read-project refresh)))
    (my/gitlab-pipelines--fetch project 1 "all" "all" "id")))

(defun my/gitlab-pipelines-mouse-browse (event)
  "Open the pipeline under the mouse in the browser."
  (interactive "e")
  (mouse-set-point event)
  (my/gitlab-dash-browse-at-point))

(defvar gitlab-pipelines-mode-map
  (let ((map (my/gitlab-dash--bind (make-sparse-keymap) 'my/gitlab-dash-browse-at-point)))
    (define-key map (kbd "w") 'my/gitlab-pipelines-watch-at-point)
    (define-key map [mouse-1] 'my/gitlab-pipelines-mouse-browse)
    (define-key map [mouse-2] 'my/gitlab-pipelines-mouse-browse)
    map)
  "Keymap for the GitLab pipeline dashboard.")

(define-derived-mode gitlab-pipelines-mode special-mode "GitLab-Pipelines"
  "Major mode for the GitLab pipeline dashboard.
\\{gitlab-pipelines-mode-map}"
  (setq truncate-lines t))

(with-eval-after-load 'evil
  (evil-set-initial-state 'gitlab-pipelines-mode 'normal)
  (my/gitlab-dash--evil-bind gitlab-pipelines-mode-map 'my/gitlab-dash-browse-at-point)
  ;; :: Same reason as `my/gitlab-dash--evil-bind': evil's state maps outrank
  ;; :: the mode map, so `w' (forward-word) and the mouse would otherwise win
  (evil-define-key* 'normal gitlab-pipelines-mode-map
    (kbd "w") 'my/gitlab-pipelines-watch-at-point
    [mouse-1] 'my/gitlab-pipelines-mouse-browse
    [mouse-2] 'my/gitlab-pipelines-mouse-browse))

;; :: Watch -- reminders.org entry + background poll

(defun my/gitlab-pipelines--watch-title (pipeline project)
  "Return the reminders.org heading text for PIPELINE of PROJECT."
  (format "Pipeline #%s · %s · %s"
          (gethash "id" pipeline) (gethash "ref" pipeline)
          (gethash "path_with_namespace" project)))

(defun my/gitlab-pipelines--watches ()
  "Return every pipeline still being watched, as plists.
Each has :project and :pipeline (strings, as org stores them) and
:heading.  Read from a throwaway buffer so a live reminders.org buffer is
never touched -- the same idiom as `my/reminders--scheduled-between'.
Returns nil when reminders.el is not loaded or the file does not exist."
  (let ((file (bound-and-true-p my/reminders-file))
        hits)
    (when (and file (file-exists-p file))
      (with-temp-buffer
        (insert-file-contents file)
        (delay-mode-hooks (org-mode))
        (org-map-entries
         (lambda ()
           (let ((pipeline (org-entry-get nil "GITLAB_PIPELINE")))
             (when (and pipeline (not (org-entry-is-done-p)))
               (push (list :project (org-entry-get nil "GITLAB_PROJECT")
                           :pipeline pipeline
                           :heading (org-get-heading t t t t))
                     hits)))))))
    (nreverse hits)))

(defun my/gitlab-pipelines--redraw ()
  "Redraw the current dashboard from the items already in hand, without a refetch."
  (my/gitlab-pipelines--render (current-buffer) my/gitlab-pipelines--project
                               my/gitlab-dash--items
                               my/gitlab-dash--page my/gitlab-dash--state
                               my/gitlab-dash--scope my/gitlab-dash--sort
                               my/gitlab-pipelines--details))

(defun my/gitlab-pipelines--open-watch-pos (pipeline-id)
  "Return the position of the still-open watch heading for PIPELINE-ID, or nil.
Filters on the TODO state rather than using `org-find-property', which
returns the first heading with that id -- after an unwatch and re-watch
that would be the old DONE one, and the new watch would never complete."
  (save-restriction
    (widen)
    (car (delq nil (org-map-entries
                    (lambda () (unless (org-entry-is-done-p) (point)))
                    (format "GITLAB_PIPELINE=\"%s\"" pipeline-id))))))

(defun my/gitlab-pipelines--mark-done (pipeline-id status)
  "Flip the open watch heading for PIPELINE-ID to DONE, recording STATUS.
Return the heading text when an open watch was found, nil otherwise --
two poll callbacks can land for one watch, and only the first should act."
  (let ((file (bound-and-true-p my/reminders-file)))
    (when (and file (file-exists-p file))
      (with-current-buffer (find-file-noselect file)
        (save-excursion
          (let ((pos (my/gitlab-pipelines--open-watch-pos pipeline-id)))
            (when pos
              (goto-char pos)
              (org-todo "DONE")
              (org-entry-put nil "GITLAB_STATUS" status)
              (save-buffer)
              (org-get-heading t t t t))))))))

(defun my/gitlab-pipelines--watched-p (pipeline-id)
  "Return non-nil when PIPELINE-ID (a string) has an open watch."
  (seq-find (lambda (w) (equal (plist-get w :pipeline) pipeline-id))
            (my/gitlab-pipelines--watches)))

(defun my/gitlab-pipelines-watch-at-point ()
  "Watch the pipeline on the current line, or stop watching it if you already are.
Watching appends a TODO heading (no SCHEDULED time, so `appt' ignores it)
to the active vault's reminders.org and starts the background poll; a
desktop notification arrives when the pipeline reaches a terminal status.
Unwatching marks that heading DONE with `:GITLAB_STATUS: unwatched'."
  (interactive)
  (let* ((pl (my/gitlab-dash--at-point))
         (project my/gitlab-pipelines--project)
         (file (or (bound-and-true-p my/reminders-file)
                   (user-error "reminders.el is not loaded -- nowhere to store the watch")))
         (id (format "%s" (gethash "id" pl)))
         (status (gethash "status" pl)))
    (cond
     ((my/gitlab-pipelines--watched-p id)
      (my/gitlab-pipelines--mark-done id "unwatched")
      (unless (my/gitlab-pipelines--watches)
        (my/gitlab-pipelines--stop-polling))
      (my/gitlab-pipelines--redraw)
      (message "Stopped watching pipeline #%s" id))
     ((my/gitlab-pipelines--terminal-p status)
      (user-error "Pipeline #%s already finished (%s)" id status))
     (t
      (with-current-buffer (find-file-noselect file)
        (save-excursion
          (when (= (point-min) (point-max))
            (insert my/reminders-file-header))
          (goto-char (point-max))
          (skip-chars-backward "\n")
          (delete-region (point) (point-max))   ;; :: same trim as `my/reminders-add'
          ;; :: No trailing newline: point has to stay ON the heading, because
          ;; :: that is the entry `org-entry-put' acts on
          (insert "\n\n* TODO " (my/gitlab-pipelines--watch-title pl project))
          (org-entry-put nil "GITLAB_PROJECT" (format "%s" (gethash "id" project)))
          (org-entry-put nil "GITLAB_PIPELINE" id)
          (org-entry-put nil "GITLAB_REF" (or (gethash "ref" pl) ""))
          (org-entry-put nil "URL" (or (gethash "web_url" pl) "")))
        (save-buffer))
      (my/gitlab-pipelines--ensure-polling)
      (my/gitlab-pipelines--redraw)   ;; :: so the ● shows without a refetch
      (message "Watching pipeline #%s -- polling every %d min, press w again to stop"
               id (max 1 (/ my/gitlab-pipelines-poll-interval 60)))))))

(defun my/gitlab-pipelines--ensure-polling ()
  "Start the watch poll timer unless it is already running."
  (unless (memq my/gitlab-pipelines--poll-timer timer-list)
    (setq my/gitlab-pipelines--poll-timer
          (run-with-timer my/gitlab-pipelines-poll-interval
                          my/gitlab-pipelines-poll-interval
                          #'my/gitlab-pipelines--poll))))

(defun my/gitlab-pipelines--stop-polling ()
  "Cancel the watch poll timer."
  (when (timerp my/gitlab-pipelines--poll-timer)
    (cancel-timer my/gitlab-pipelines--poll-timer))
  (setq my/gitlab-pipelines--poll-timer nil))

(defun my/gitlab-pipelines--complete-watch (watch status)
  "Mark WATCH done with STATUS in reminders.org and send a notification.
Stops the poll timer when no watches remain."
  (let ((pipeline (plist-get watch :pipeline)))
    (when (my/gitlab-pipelines--mark-done pipeline status)
      (my/reminders--deliver (format "Pipeline %s" status)
                             (plist-get watch :heading)
                             (and (equal status "failed") "critical"))
      (message "Pipeline #%s finished: %s" pipeline status))
    (unless (my/gitlab-pipelines--watches)
      (my/gitlab-pipelines--stop-polling))))

(defun my/gitlab-pipelines--poll ()
  "Check every watched pipeline once; stop polling when none are left.
Runs from a timer, so an error here (the token lookup can signal) is
reported and swallowed rather than left to spam the timer."
  (condition-case err
      (let ((watches (my/gitlab-pipelines--watches)))
        (if (null watches)
            (my/gitlab-pipelines--stop-polling)
          (dolist (watch watches)
            (my/gitlab--api-get-async
             (format "projects/%s/pipelines/%s"
                     (plist-get watch :project) (plist-get watch :pipeline))
             ""
             (lambda (data)
               (when (my/gitlab--has-key data "status")
                 (let ((status (gethash "status" data)))
                   (when (my/gitlab-pipelines--terminal-p status)
                     (my/gitlab-pipelines--complete-watch watch status)))))))))
    (error (message "GitLab pipeline poll failed: %s" (error-message-string err)))))

(defun my/gitlab-pipelines--resume-polling ()
  "Restart the watch poll after an Emacs restart if watches are still pending."
  (when (my/gitlab-pipelines--watches)
    (my/gitlab-pipelines--ensure-polling)))

;; :: reminders.el (and with it `my/reminders-file') is loaded AFTER this
;; :: module in config.el, so resume from an idle timer rather than at load.
;; :: Not in the "notes" daemon: both Emacsen share reminders.org, so resuming
;; :: in both would poll GitLab twice and could notify twice per pipeline.
;; :: Watches are a coding-session thing; `w' still works there by hand.
(unless (bound-and-true-p my/notes-instance-p)
  (run-with-idle-timer 30 nil #'my/gitlab-pipelines--resume-polling))

;;; pipelines.el ends here
