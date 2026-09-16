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
;; ::    # GITLAB_ISSUES_DIR is optional: it applies only in vault flat mode.
;; ::    # With a vault active the issue dir is derived from it -- leave it unset.
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

(defun my/gitlab-issues-relative-dir ()
  ":: vault-relative path to the issue files. A function, not a constant,
   because it depends on `my/gitlab-project-name'."
  (format "projects/%s/issues/" my/gitlab-project-name))

(defun my/gitlab-issues-dir ()
  "Return the directory holding the local GitLab issue files.
Resolved at call time from `my/notes-dir', so it always tracks the active
vault -- and any `my/with-vault' binding -- with nothing to go stale.
GITLAB_ISSUES_DIR is honoured only in flat mode (no active vault): with a
vault active the vault wins, so a stale `doom env' snapshot of that
variable cannot pin issues to a tree outside the vault."
  (file-name-as-directory
   (expand-file-name
    (or (and (not (bound-and-true-p my/vault)) (getenv "GITLAB_ISSUES_DIR"))
        (concat my/notes-dir (my/gitlab-issues-relative-dir))))))

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

(defun my/gitlab--decode-body (raw)
  "Return RAW decoded as UTF-8, whichever representation the buffer used."
  (cond
   ((not (multibyte-string-p raw)) (decode-coding-string raw 'utf-8))
   ;; :: Multibyte, but no character above a byte value -- still raw bytes
   ((not (string-match-p "[^\000-\377]" raw))
    (decode-coding-string (encode-coding-string raw 'latin-1) 'utf-8))
   (t raw)))

(defun my/gitlab--read-json-body ()
  "Parse the JSON body of the `url-retrieve' response in the current buffer.
Objects become hash-tables and arrays lists.

The response buffer holds *undecoded bytes*, so calling `json-read' on it
directly turns every multi-byte UTF-8 character into one character per
byte -- that is where the `\u00e2' and `\u00f0' in older issue filenames came
from.  Decoding the body as UTF-8 first keeps em dashes and emoji intact."
  (let ((body (my/gitlab--decode-body
               (buffer-substring-no-properties
                (if (markerp url-http-end-of-headers)
                    (marker-position url-http-end-of-headers)
                  url-http-end-of-headers)
                (point-max)))))
    (with-temp-buffer
      (insert body)
      (goto-char (point-min))
      (let ((json-object-type 'hash-table)
            (json-array-type 'list)
            (json-key-type 'string))
        (json-read)))))

(defun my/gitlab--issue-link-text (filepath display-text)
  "Return an org or markdown link to FILEPATH with DISPLAY-TEXT for the current buffer.
Org links use the vault abbreviation (`work:projects/...') so they resolve on
both the macOS and Linux roots; markdown keeps the plain path."
  (if (derived-mode-p 'org-mode)
      (format "[[%s][%s]]" (my/org-link-abbreviate filepath) display-text)
    (format "[%s](%s)" display-text filepath)))

(defun my/gitlab--issue-files ()
  "Return basenames of issue files in `my/gitlab-issues-dir', newest issue first."
  (let ((issues-dir (my/gitlab-issues-dir)))
    (when (file-directory-p issues-dir)
      (sort
       (directory-files
        issues-dir nil
        (format "^%s#[0-9]+ - .*\\.org$" (regexp-quote my/gitlab-project-name)))
       #'string>))))

(defvar my/gitlab--issues-index nil
  "Cached (DIRECTORY . ALIST) of local issue files, or nil when not built.
ALIST maps DISPLAY -- the file's real `#+TITLE', so completion matches the
full, unsanitized issue title -- to FILENAME.  Keying on DIRECTORY means a
vault switch rebuilds instead of serving the previous vault's issues.
Invalidated automatically when an issue file is written; refresh manually
with `my/gitlab-refresh-issues-index' after external changes (e.g. git pull).")

(defun my/gitlab--issue-file-title (filepath)
  "Return the `#+TITLE' of FILEPATH, or nil if absent."
  (with-temp-buffer
    (insert-file-contents filepath nil 0 4096)
    (goto-char (point-min))
    (when (re-search-forward "^#\\+TITLE:[ \t]*\\(.*\\)$" nil t)
      (string-trim (match-string 1)))))

(defun my/gitlab--build-issues-index ()
  "Scan `my/gitlab-issues-dir' and return an alist of (DISPLAY . FILENAME).
DISPLAY is each file's `#+TITLE' (falling back to its basename)."
  (let ((issues-dir (my/gitlab-issues-dir)))
    (mapcar
     (lambda (f)
       (cons (or (my/gitlab--issue-file-title (expand-file-name f issues-dir))
                 (file-name-sans-extension f))
             f))
     (my/gitlab--issue-files))))

(defun my/gitlab--issues-index ()
  "Return the issue completion index for the active vault, cached per directory."
  (let ((dir (my/gitlab-issues-dir)))
    (if (equal (car my/gitlab--issues-index) dir)
        (cdr my/gitlab--issues-index)
      (cdr (setq my/gitlab--issues-index
                 (cons dir (my/gitlab--build-issues-index)))))))

(defun my/gitlab-refresh-issues-index ()
  "Invalidate the cached issues index so the next pick re-scans the directory.
Use after files are added or renamed outside Emacs (e.g. a git pull)."
  (interactive)
  (setq my/gitlab--issues-index nil)
  (message "GitLab issues index cleared; rebuilding on next use"))

(defun my/gitlab--existing-file-for-id (issue-id)
  "Return the basename of the local file for ISSUE-ID, or nil if none exists."
  (let ((issues-dir (my/gitlab-issues-dir)))
    (when (file-directory-p issues-dir)
      (car (directory-files
            issues-dir nil
            (format "^%s#%s - .*\\.org$"
                    (regexp-quote my/gitlab-project-name) issue-id))))))

(defun my/gitlab--insert-issue-file-link (filename)
  "Insert a link at point to FILENAME (a basename in `my/gitlab-issues-dir')."
  (let* ((filepath (expand-file-name filename (my/gitlab-issues-dir)))
         (base (file-name-sans-extension filename))
         (display-text
          (if (string-match
               (format "^%s#\\([0-9]+\\) - \\(.*\\)$" (regexp-quote my/gitlab-project-name))
               base)
              (format "%s#%s - %s"
                      my/gitlab-project-name
                      (match-string 1 base)
                      (my/gitlab-escape-org-title (match-string 2 base)))
            (my/gitlab-escape-org-title base))))
    (insert (my/gitlab--issue-link-text filepath display-text))
    (message "Inserted link to: %s" filename)))

(defun my/gitlab--completion-table (candidates)
  "Return a completion table over CANDIDATES (an alist) that preserves their order."
  (lambda (string pred action)
    (if (eq action 'metadata)
        '(metadata (display-sort-function . identity)
          (cycle-sort-function . identity))
      (complete-with-action action candidates string pred))))

(defun my/gitlab--api-get-sync (path query-string)
  "GET /api/v4/PATH?QUERY-STRING synchronously and return parsed JSON.
Objects are hash-tables and arrays are lists.  Signals an error on failure."
  (let* ((token (my/gitlab-get-token))
         (url (format "%s/api/v4/%s?%s" my/gitlab-url path query-string))
         (url-request-method "GET")
         (url-request-extra-headers `(("PRIVATE-TOKEN" . ,token)))
         (buf (url-retrieve-synchronously url t t 30)))
    (unless buf (error "GitLab request failed or timed out: %s" url))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (unless (re-search-forward "\n\n" nil t)
            (error "Malformed response from GitLab"))
          (let ((json-object-type 'hash-table)
                (json-array-type 'list)
                (json-key-type 'string))
            (json-read)))
      (kill-buffer buf))))

(defun my/gitlab--write-issue-file (issue-id json)
  "Create the local org file for ISSUE-ID from JSON (a hash-table).
Return the filepath of the created file."
  (let* ((issues-dir (my/gitlab-issues-dir))
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
         (filepath (expand-file-name filename issues-dir))
         (org-description
          (if (string-empty-p description)
              ""
            (with-temp-buffer
              (insert description)
              (shell-command-on-region
               (point-min) (point-max)
               "pandoc -f markdown -t org"
               (current-buffer) t)
              (buffer-string)))))

    (make-directory issues-dir t)
    (with-temp-file filepath
      (insert (format "#+TITLE: %s#%s - %s\n" my/gitlab-project-name issue-id title))
      (insert (format "#+DATE: %s\n\n" (format-time-string "%Y-%m-%d")))
      (insert (format "* Issue Details\n\n"))
      (insert (format "- *Status:* %s\n" state))
      (insert (format "- *URL:* [[%s][GitLab Issue #%s]]\n" web-url issue-id))
      (when author
        (insert (format "- *Author:* %s\n" (gethash "name" author))))
      (when labels
        (insert (format "- *Labels:* %s\n" (mapconcat 'identity labels ", "))))
      (when milestone
        (insert (format "- *Milestone:* %s\n" (gethash "title" milestone))))
      (when assignees
        (insert (format "- *Assignees:* %s\n"
                        (mapconcat (lambda (a) (gethash "name" a)) assignees ", "))))
      (insert (format "- *Created:* %s\n"
                      (format-time-string "%Y-%m-%d %H:%M" (date-to-time created-at))))
      (insert (format "- *Updated:* %s\n"
                      (format-time-string "%Y-%m-%d %H:%M" (date-to-time updated-at))))
      (when closed-at
        (insert (format "- *Closed:* %s\n"
                        (format-time-string "%Y-%m-%d %H:%M" (date-to-time closed-at)))))
      (insert "\n* Description\n\n")
      (insert org-description)
      (insert "\n\n* Notes\n\n"))
    ;; :: A new file changed the directory; force a rebuild on next pick
    (setq my/gitlab--issues-index nil)
    filepath))

(defun my/gitlab--save-issue-object-and-link (issue-id json)
  "Write the file for ISSUE-ID from JSON (reusing a local file if present) and link it."
  (let ((existing (my/gitlab--existing-file-for-id issue-id)))
    (if existing
        (my/gitlab--insert-issue-file-link existing)
      (let* ((filepath (my/gitlab--write-issue-file issue-id json))
             (display-text (format "%s#%s - %s"
                                   my/gitlab-project-name issue-id
                                   (my/gitlab-escape-org-title (gethash "title" json)))))
        (insert (my/gitlab--issue-link-text filepath display-text))
        (message "Saved and linked: %s" (file-name-nondirectory filepath))))))

(defun my/gitlab--fetch-create-and-link (issue-id)
  "Fetch ISSUE-ID from the API, create its org file, then insert a link at point."
  (let* ((token (my/gitlab-get-token))
         (project-id-encoded (url-hexify-string my/gitlab-project-id))
         (api-url (format "%s/api/v4/projects/%s/issues/%s"
                          my/gitlab-url
                          project-id-encoded
                          issue-id))
         (url-request-extra-headers
          `(("PRIVATE-TOKEN" . ,token)))
         (url-request-method "GET")
         ;; :: url-retrieve is async; capture where to insert the link
         (target-marker (copy-marker (point) t)))

    (url-retrieve api-url
                  (lambda (status)
                    (if (plist-get status :error)
                        (message "Error fetching issue: %s" (plist-get status :error))
                      (let* ((json (my/gitlab--read-json-body))
                             (filepath (my/gitlab--write-issue-file issue-id json))
                             (filename (file-name-nondirectory filepath))
                             (display-text (format "%s#%s - %s"
                                                   my/gitlab-project-name issue-id
                                                   (my/gitlab-escape-org-title (gethash "title" json)))))
                        (if (buffer-live-p (marker-buffer target-marker))
                            (with-current-buffer (marker-buffer target-marker)
                              (save-excursion
                                (goto-char target-marker)
                                (insert (my/gitlab--issue-link-text filepath display-text)))
                              (message "Created file and inserted link: %s" filename))
                          (message "Created file %s; buffer gone, link not inserted" filename)))))
                  nil t)))

(defun my/gitlab--search-select-issue (query)
  "Search the project's issues for QUERY and return the selected issue object, or nil."
  (message "Searching GitLab issues for %S..." query)
  (let* ((project-id-encoded (url-hexify-string my/gitlab-project-id))
         (results (my/gitlab--api-get-sync
                   (format "projects/%s/issues" project-id-encoded)
                   (format "search=%s&per_page=20&order_by=updated_at&sort=desc"
                           (url-hexify-string query)))))
    (if (null results)
        (progn (message "No GitLab issues found for %S" query) nil)
      (let* ((candidates
              (mapcar (lambda (issue)
                        (cons (format "#%s  %s  [%s]"
                                      (gethash "iid" issue)
                                      (gethash "title" issue)
                                      (gethash "state" issue))
                              issue))
                      results))
             (choice (completing-read
                      (format "Select issue (%d found): " (length results))
                      (my/gitlab--completion-table candidates) nil t)))
        (cdr (assoc choice candidates))))))

(defun my/gitlab--search-and-link (query)
  "Search the project's issues for QUERY, let the user pick one, save it, and link it."
  (let ((issue (my/gitlab--search-select-issue query)))
    (when issue
      (my/gitlab--save-issue-object-and-link
       (number-to-string (gethash "iid" issue)) issue))))

(defun my/gitlab--open-issue-file (filename)
  "Open the local issue file FILENAME (a basename in `my/gitlab-issues-dir')."
  (find-file (expand-file-name filename (my/gitlab-issues-dir)))
  (message "Opened: %s" filename))

(defun my/gitlab--save-issue-object-and-open (issue-id json)
  "Write the file for ISSUE-ID from JSON (reusing a local file if present) and open it."
  (let ((existing (my/gitlab--existing-file-for-id issue-id)))
    (if existing
        (my/gitlab--open-issue-file existing)
      (let ((filepath (my/gitlab--write-issue-file issue-id json)))
        (find-file filepath)
        (message "Saved and opened: %s" (file-name-nondirectory filepath))))))

(defun my/gitlab--fetch-create-and-open (issue-id)
  "Fetch ISSUE-ID from the API, create its org file, and open it."
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
                      (let* ((json (my/gitlab--read-json-body))
                             (filepath (my/gitlab--write-issue-file issue-id json)))
                        (find-file filepath)
                        (message "Created and opened issue #%s - %s"
                                 issue-id (gethash "title" json)))))
                  nil t)))

(defun my/gitlab--search-and-open (query)
  "Search the project's issues for QUERY, let the user pick one, save it, and open it."
  (let ((issue (my/gitlab--search-select-issue query)))
    (when issue
      (my/gitlab--save-issue-object-and-open
       (number-to-string (gethash "iid" issue)) issue))))

(defun my/gitlab-fetch-issue (&optional issue-id)
  "Insert a link to a GitLab issue's local org file at point.

Called interactively with no ISSUE-ID, prompts with completion over the
existing issue files in `my/gitlab-issues-dir' -- type to search by
filename and select one to insert its link.  If the input does not match a
local file:
  - a pure issue ID is fetched directly from the API; or
  - free text is sent to the GitLab issue search API (scoped to this
    project), and you pick a match from the results.
In both cases the issue is saved locally and a link is inserted."
  (interactive)
  (my/gitlab-check-config)
  (if issue-id
      ;; :: Programmatic path: link existing file or fetch+create
      (let ((existing (my/gitlab--existing-file-for-id issue-id)))
        (if existing
            (my/gitlab--insert-issue-file-link existing)
          (my/gitlab--fetch-create-and-link issue-id)))
    (let* ((candidates (my/gitlab--issues-index))
           (choice (string-trim
                    (completing-read
                     "GitLab issue (pick local; or type ID / search text): "
                     (my/gitlab--completion-table candidates) nil nil)))
           (match (assoc choice candidates)))
      (cond
       ;; :: Empty input
       ((string-empty-p choice) (message "No issue selected"))
       ;; :: Picked an existing local file
       (match (my/gitlab--insert-issue-file-link (cdr match)))
       ;; :: Pure issue ID -- reuse local file if present, else fetch by IID
       ((string-match-p "\\`[0-9]+\\'" choice)
        (let ((existing (my/gitlab--existing-file-for-id choice)))
          (if existing
              (my/gitlab--insert-issue-file-link existing)
            (my/gitlab--fetch-create-and-link choice))))
       ;; :: Free text -- search remote issues and pick one
       (t (my/gitlab--search-and-link choice))))))

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
      :desc "GitLab Refresh Issue Index" "g R" #'my/gitlab-refresh-issues-index
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


(defun my/gitlab-lookup-issue (&optional issue-id)
  "Open a GitLab issue's local org file, creating it from the API if needed.

Called interactively with no ISSUE-ID, prompts with completion over the
existing issue files in `my/gitlab-issues-dir' -- type to search by
filename and select one to open it.  If the input does not match a local
file:
  - a pure issue ID is fetched directly from the API; or
  - free text is sent to the GitLab issue search API (scoped to this
    project), and you pick a match from the results.
In both cases the issue is saved locally and the file is opened."
  (interactive)
  (my/gitlab-check-config)
  (if issue-id
      ;; :: Programmatic path: open existing file or fetch+create+open
      (let ((existing (my/gitlab--existing-file-for-id issue-id)))
        (if existing
            (my/gitlab--open-issue-file existing)
          (my/gitlab--fetch-create-and-open issue-id)))
    (let* ((candidates (my/gitlab--issues-index))
           (choice (string-trim
                    (completing-read
                     "GitLab issue (pick local; or type ID / search text): "
                     (my/gitlab--completion-table candidates) nil nil)))
           (match (assoc choice candidates)))
      (cond
       ;; :: Empty input
       ((string-empty-p choice) (message "No issue selected"))
       ;; :: Picked an existing local file
       (match (my/gitlab--open-issue-file (cdr match)))
       ;; :: Pure issue ID -- reuse local file if present, else fetch by IID
       ((string-match-p "\\`[0-9]+\\'" choice)
        (let ((existing (my/gitlab--existing-file-for-id choice)))
          (if existing
              (my/gitlab--open-issue-file existing)
            (my/gitlab--fetch-create-and-open choice))))
       ;; :: Free text -- search remote issues and pick one
       (t (my/gitlab--search-and-open choice))))))

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
                      (let* ((json (my/gitlab--read-json-body))
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
         (issues-dir (my/gitlab-issues-dir))
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
                        (let* ((json (my/gitlab--read-json-body))
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
         (issues-dir (my/gitlab-issues-dir))
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
                        (let* ((mrs (my/gitlab--read-json-body)))
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
  (expand-file-name "templates/merge_request_template.md" my/notes-dir)
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
(defvar-local my/gitlab-mr--iid nil
  "IID of the existing MR being edited in this buffer.")

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

(defun my/gitlab-copy-mr-link ()
  "Copy the MR link for the current branch to the kill-ring.
Uses glab to look up the merge request whose source branch matches
the current branch. If none is found, reports that no MR exists yet."
  (interactive)
  (unless (executable-find "glab")
    (error "glab CLI not found on PATH"))
  (let* ((dir (or (vc-root-dir)
                  (error "Not inside a version-controlled repository")))
         (branch (or (my/gitlab-mr--current-branch dir)
                     (error "Could not determine current branch")))
         (default-directory dir))
    (with-temp-buffer
      (if (zerop (process-file "glab" nil t nil
                               "mr" "list"
                               "--source-branch" branch
                               "--output" "json"))
          (let* ((json-object-type 'hash-table)
                 (json-array-type 'list)
                 (json-key-type 'string)
                 (mrs (progn (goto-char (point-min)) (json-read)))
                 (mr (car mrs)))
            (if mr
                (let ((url (gethash "web_url" mr)))
                  (kill-new url)
                  (message "MR link copied: %s" url))
              (message "No MR for this branch yet")))
        (message "No MR for this branch yet")))))

(defun my/gitlab-browse-remote ()
  "Open the current repository's GitLab project page in the browser.
Uses `glab repo view --web', which resolves the page from the repo's
origin remote -- no URL parsing needed here."
  (interactive)
  (unless (executable-find "glab")
    (error "glab CLI not found on PATH"))
  (let* ((dir (or (vc-root-dir)
                  (error "Not inside a version-controlled repository")))
         (default-directory dir))
    (with-temp-buffer
      (unless (zerop (process-file "glab" nil t nil "repo" "view" "--web"))
        (error "glab repo view --web failed: %s" (string-trim (buffer-string)))))))

(defun my/gitlab-edit-mr ()
  "Edit the description of the existing MR for the current branch.
Errors if no MR exists. Otherwise opens an editable buffer pre-filled with
the MR's current description (markdown). Press \\[my/gitlab-mr-edit-submit]
to save or \\[my/gitlab-mr-cancel] to abort."
  (interactive)
  (unless (executable-find "glab")
    (error "glab CLI not found on PATH"))
  (let* ((dir (or (vc-root-dir)
                  (error "Not inside a version-controlled repository")))
         (source (or (my/gitlab-mr--current-branch dir)
                     (error "Could not determine current branch")))
         (default-directory dir)
         (mr (with-temp-buffer
               (unless (zerop (process-file "glab" nil t nil
                                            "mr" "list"
                                            "--source-branch" source
                                            "--output" "json"))
                 (error "No MR for this branch yet"))
               (let* ((json-object-type 'hash-table)
                      (json-array-type 'list)
                      (json-key-type 'string))
                 (goto-char (point-min))
                 (car (json-read))))))
    (unless mr
      (error "No MR for this branch yet"))
    (let* ((iid (gethash "iid" mr))
           (title (gethash "title" mr))
           (description (or (gethash "description" mr) ""))
           (buf (get-buffer-create "*GitLab MR Edit*")))
      (with-current-buffer buf
        (erase-buffer)
        (insert description)
        (if (fboundp 'gfm-mode) (gfm-mode) (text-mode))
        (setq my/gitlab-mr--iid iid
              my/gitlab-mr--title title
              my/gitlab-mr--source source
              my/gitlab-mr--directory dir)
        (use-local-map (copy-keymap (current-local-map)))
        (local-set-key (kbd "C-c C-c") #'my/gitlab-mr-edit-submit)
        (local-set-key (kbd "C-c C-k") #'my/gitlab-mr-cancel)
        (setq header-line-format
              (format " Edit MR !%s: %s   |   C-c C-c: save   C-c C-k: cancel"
                      iid title))
        (goto-char (point-min)))
      (pop-to-buffer buf)
      (message "Edit the MR description, then C-c C-c to save (C-c C-k to cancel)"))))

(defun my/gitlab-mr-edit-submit ()
  "Save the edited MR description in the current buffer via glab."
  (interactive)
  (let* ((iid my/gitlab-mr--iid)
         (dir my/gitlab-mr--directory)
         (description (buffer-substring-no-properties (point-min) (point-max)))
         (default-directory dir)
         (out-buf (get-buffer-create "*glab mr update*")))
    (unless iid
      (error "No MR associated with this buffer"))
    (with-current-buffer out-buf
      (let ((inhibit-read-only t)) (erase-buffer))
      (setq default-directory dir))
    (message "Updating merge request...")
    (make-process
     :name "glab-mr-update"
     :buffer out-buf
     :command (list "glab" "mr" "update" (number-to-string iid)
                    "--description" description)
     :sentinel
     (lambda (proc _event)
       (when (memq (process-status proc) '(exit signal))
         (if (zerop (process-exit-status proc))
             (progn
               (when (buffer-live-p (get-buffer "*GitLab MR Edit*"))
                 (kill-buffer "*GitLab MR Edit*"))
               (message "MR !%s updated" iid))
           (progn
             (pop-to-buffer out-buf)
             (message "glab mr update failed (see *glab mr update*)"))))))))

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
      :desc "GitLab Create MR" "g M" #'my/gitlab-create-mr
      :desc "GitLab Copy MR Link" "g y" #'my/gitlab-copy-mr-link
      :desc "GitLab Edit MR" "g e" #'my/gitlab-edit-mr
      :desc "GitLab Browse Remote" "g b" #'my/gitlab-browse-remote)



;; :: ============================================================
;; :: Dashboards: my merge requests / my assigned issues
;; :: ============================================================
;;
;; :: `my/gitlab-my-merge-requests' (SPC o g p) and `my/gitlab-my-issues'
;; :: (SPC o g a) list your work one line each, newest first, so pending MRs
;; :: and tickets can be checked without going to Slack or GitLab.
;; ::
;; :: Both share `my/gitlab-dash--*': paging, state/scope/sort cycling and
;; :: refresh live in one place, and each dashboard supplies its own renderer
;; :: and its own RET action.

(defvar my/gitlab-dash-per-page 20
  "How many items each GitLab dashboard fetches per page.")

;; :: ------------------------------------------------------------
;; :: Small shared helpers
;; :: ------------------------------------------------------------

(defun my/gitlab--truthy (value)
  "Return non-nil when VALUE is JSON true.
`json-read' decodes false as `:json-false', which is itself truthy in
elisp -- every boolean field from the API has to go through here."
  (and value (not (eq value :json-false))))

(defun my/gitlab--has-key (table key)
  "Return non-nil when hash-table TABLE actually carries KEY.
Distinguishes \"field absent from this GitLab version\" from \"field is
false/empty\" -- both decode to nil otherwise."
  (and (hash-table-p table)
       (not (eq 'missing (gethash key table 'missing)))))

(defun my/gitlab--truncate (string width)
  "Pad or ellipsise STRING to exactly WIDTH display columns."
  (truncate-string-to-width (or string "") width nil ?\s "…"))

(defun my/gitlab--relative-time (iso)
  "Return a compact age (e.g. \"3d\") for the ISO 8601 timestamp ISO."
  (if (not iso)
      "?"
    (let ((secs (float-time (time-subtract (current-time) (date-to-time iso)))))
      (cond
       ((< secs 3600) (format "%dm" (max 1 (floor (/ secs 60)))))
       ((< secs 86400) (format "%dh" (floor (/ secs 3600))))
       ((< secs 2592000) (format "%dd" (floor (/ secs 86400))))
       (t (format "%dmo" (floor (/ secs 2592000))))))))

(defun my/gitlab--md-to-org (markdown)
  "Convert MARKDOWN to org via pandoc, returning MARKDOWN unchanged if absent."
  (cond
   ((or (null markdown) (string-empty-p markdown)) "")
   ((not (executable-find "pandoc")) markdown)
   (t (with-temp-buffer
        (insert markdown)
        (shell-command-on-region
         (point-min) (point-max) "pandoc -f markdown -t org" (current-buffer) t)
        (buffer-string)))))

(defun my/gitlab--indent-block (text prefix)
  "Prefix every line of TEXT with PREFIX."
  (mapconcat (lambda (line) (concat prefix line))
             (split-string (or text "") "\n")
             "\n"))

(defun my/gitlab--scoped-label (labels scope)
  "Return the value of the first SCOPE:: scoped label in LABELS, or nil.
GitLab scoped labels (`stage::refine', `priority::high') are where the
real workflow status lives, so they get their own dashboard columns."
  (let ((prefix (concat scope "::")))
    (seq-some (lambda (label)
                (and (string-prefix-p prefix label)
                     (substring label (length prefix))))
              labels)))

(defun my/gitlab--api-request-async (method path query-string callback)
  "Send METHOD to /api/v4/PATH?QUERY-STRING and call CALLBACK with parsed JSON.
Objects are hash-tables, arrays are lists.  CALLBACK receives nil when the
request itself fails; HTTP-level errors arrive as a payload carrying a
\"message\" key, so callers that care should check for the fields they need."
  (let* ((token (my/gitlab-get-token))
         (url (format "%s/api/v4/%s%s" my/gitlab-url path
                      (if (and query-string (not (string-empty-p query-string)))
                          (concat "?" query-string)
                        "")))
         (url-request-method method)
         (url-request-extra-headers `(("PRIVATE-TOKEN" . ,token))))
    (url-retrieve
     url
     (lambda (status)
       (if (plist-get status :error)
           (progn (message "GitLab request failed: %s" (plist-get status :error))
                  (funcall callback nil))
         (funcall callback (my/gitlab--read-json-body))))
     nil t)))

(defun my/gitlab--api-get-async (path query-string callback)
  "GET /api/v4/PATH?QUERY-STRING and call CALLBACK with the parsed JSON."
  (my/gitlab--api-request-async "GET" path query-string callback))

;; :: ------------------------------------------------------------
;; :: Shared dashboard layer
;; :: ------------------------------------------------------------

(defvar-local my/gitlab-dash--refetch nil
  "Function of (PAGE STATE SCOPE SORT) that redraws this dashboard.")
(defvar-local my/gitlab-dash--page 1
  "Page currently displayed.")
(defvar-local my/gitlab-dash--state "opened"
  "State filter currently displayed.")
(defvar-local my/gitlab-dash--scope "created_by_me"
  "Scope filter currently displayed.")
(defvar-local my/gitlab-dash--sort "created_at"
  "Field the current listing is ordered by.")
(defvar-local my/gitlab-dash--items nil
  "Objects currently displayed, in render order.")
(defvar-local my/gitlab-dash--states nil
  "States `my/gitlab-dash-cycle-state' rotates through in this buffer.")
(defvar-local my/gitlab-dash--scopes nil
  "Scopes `my/gitlab-dash-cycle-scope' rotates through in this buffer.")
(defvar-local my/gitlab-dash--sorts nil
  "Sort fields `my/gitlab-dash-cycle-sort' rotates through in this buffer.")

(defun my/gitlab-dash--next-in (value list)
  "Return the entry after VALUE in LIST, wrapping around."
  (or (cadr (member value list)) (car list)))

(defun my/gitlab-dash--go (&rest overrides)
  "Re-fetch this dashboard.
OVERRIDES is a plist of :page, :state, :scope and :sort; anything absent
keeps the buffer's current value."
  (unless (functionp my/gitlab-dash--refetch)
    (user-error "Not a GitLab dashboard buffer"))
  (funcall my/gitlab-dash--refetch
           (or (plist-get overrides :page) my/gitlab-dash--page)
           (or (plist-get overrides :state) my/gitlab-dash--state)
           (or (plist-get overrides :scope) my/gitlab-dash--scope)
           (or (plist-get overrides :sort) my/gitlab-dash--sort)))

(defun my/gitlab-dash-refresh ()
  "Re-fetch the current page."
  (interactive)
  (my/gitlab-dash--go))

(defun my/gitlab-dash-next-page ()
  "Show the next page."
  (interactive)
  (if (< (length my/gitlab-dash--items) my/gitlab-dash-per-page)
      (message "Already on the last page")
    (my/gitlab-dash--go :page (1+ my/gitlab-dash--page))))

(defun my/gitlab-dash-prev-page ()
  "Show the previous page."
  (interactive)
  (if (<= my/gitlab-dash--page 1)
      (message "Already on the first page")
    (my/gitlab-dash--go :page (1- my/gitlab-dash--page))))

(defun my/gitlab-dash-cycle-state ()
  "Cycle the state filter, returning to page 1."
  (interactive)
  (my/gitlab-dash--go
   :page 1 :state (my/gitlab-dash--next-in my/gitlab-dash--state my/gitlab-dash--states)))

(defun my/gitlab-dash-cycle-scope ()
  "Cycle the scope filter, returning to page 1."
  (interactive)
  (if (< (length my/gitlab-dash--scopes) 2)
      (message "Only one scope for this view")
    (my/gitlab-dash--go
     :page 1 :scope (my/gitlab-dash--next-in my/gitlab-dash--scope my/gitlab-dash--scopes))))

(defun my/gitlab-dash-cycle-sort ()
  "Cycle the sort field, returning to page 1."
  (interactive)
  (my/gitlab-dash--go
   :page 1 :sort (my/gitlab-dash--next-in my/gitlab-dash--sort my/gitlab-dash--sorts)))

(defun my/gitlab-dash--at-point ()
  "Return the object on the current line, or signal an error."
  (or (get-text-property (point) 'gitlab-item)
      (save-excursion
        (beginning-of-line)
        (get-text-property (point) 'gitlab-item))
      (user-error "Nothing on this line")))

(defun my/gitlab-dash-browse-at-point ()
  "Open the item on the current line in the browser."
  (interactive)
  (browse-url (gethash "web_url" (my/gitlab-dash--at-point))))

(defun my/gitlab-dash-copy-url-at-point ()
  "Copy the URL of the item on the current line."
  (interactive)
  (let ((url (gethash "web_url" (my/gitlab-dash--at-point))))
    (kill-new url)
    (message "Copied: %s" url)))

(defun my/gitlab-dash--sort-label (sort)
  "Return a short human label for the SORT field."
  (if (equal sort "updated_at") "recently updated" "newest"))

(defun my/gitlab-dash--insert-header (title scope-label state sort page count columns help)
  "Insert the common dashboard header into the current buffer."
  (insert (propertize (format "%s — %s · %s · %s · page %d\n"
                              title scope-label state
                              (my/gitlab-dash--sort-label sort) page)
                      'face 'bold))
  (insert (propertize (format "%d shown%s\n" count
                              (if (< count my/gitlab-dash-per-page) " (last page)" ""))
                      'face 'font-lock-comment-face))
  (insert (propertize (concat help "\n\n") 'face 'font-lock-comment-face))
  (insert (propertize columns 'face 'font-lock-keyword-face)))

(defun my/gitlab-dash--finish (page state scope sort items states scopes sorts)
  "Record the dashboard's filter state as buffer-local variables."
  (setq my/gitlab-dash--page page
        my/gitlab-dash--state state
        my/gitlab-dash--scope scope
        my/gitlab-dash--sort sort
        my/gitlab-dash--items items
        my/gitlab-dash--states states
        my/gitlab-dash--scopes scopes
        my/gitlab-dash--sorts sorts))

(defun my/gitlab-dash--bind (map open-fn)
  "Populate MAP with the shared dashboard keys, using OPEN-FN for RET/o."
  (define-key map (kbd "RET") open-fn)
  (define-key map (kbd "o") open-fn)
  (define-key map (kbd "b") 'my/gitlab-dash-browse-at-point)
  (define-key map (kbd "y") 'my/gitlab-dash-copy-url-at-point)
  (define-key map (kbd "n") 'my/gitlab-dash-next-page)
  (define-key map (kbd "p") 'my/gitlab-dash-prev-page)
  (define-key map (kbd "s") 'my/gitlab-dash-cycle-state)
  (define-key map (kbd "t") 'my/gitlab-dash-cycle-scope)
  (define-key map (kbd "S") 'my/gitlab-dash-cycle-sort)
  (define-key map (kbd "r") 'my/gitlab-dash-refresh)
  (define-key map (kbd "q") 'quit-window)
  map)

(defun my/gitlab-dash--evil-bind (mode-map open-fn)
  "Mirror the shared dashboard keys into evil normal state for MODE-MAP.
Uses `evil-define-key*', the function form.  `evil-define-key' is a macro:
given the symbol of a lexical variable it defers the bindings to a global
keymap variable of that name, which never exists here -- so nothing binds
and evil's own RET/b/y/n/p keep winning."
  (evil-define-key* 'normal mode-map
    (kbd "RET") open-fn
    (kbd "o") open-fn
    (kbd "b") 'my/gitlab-dash-browse-at-point
    (kbd "y") 'my/gitlab-dash-copy-url-at-point
    (kbd "n") 'my/gitlab-dash-next-page
    (kbd "p") 'my/gitlab-dash-prev-page
    (kbd "s") 'my/gitlab-dash-cycle-state
    (kbd "t") 'my/gitlab-dash-cycle-scope
    (kbd "S") 'my/gitlab-dash-cycle-sort
    (kbd "r") 'my/gitlab-dash-refresh
    (kbd "gr") 'my/gitlab-dash-refresh
    (kbd "q") 'quit-window))

(defconst my/gitlab-dash-help
  "RET/o: open  b: browser  y: copy URL  n/p: page  s: state  t: scope  S: sort  r: refresh  q: quit"
  "Help line shown at the top of every GitLab dashboard.")

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

(defun my/gitlab--clean-title (title)
  "Return TITLE with any Draft:/WIP: prefix stripped.
The prefix is redundant -- draft state gets its own column."
  (replace-regexp-in-string "\\`\\(\\[?Draft\\]?\\|\\[?WIP\\]?\\):[ \t]*" ""
                            (or title "")))

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

(defun my/gitlab--project-of (item)
  "Return ITEM's `group/project' path from its references block."
  (let ((refs (gethash "references" item)))
    (if refs
        (replace-regexp-in-string "[!#].*\\'" "" (or (gethash "full" refs) ""))
      "")))

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

(defun my/gitlab--own-project-p (project-id)
  "Return non-nil when PROJECT-ID is the project `my/gitlab-project-id' names.
The local issue-file helpers key filenames off `my/gitlab-project-name',
so they only make sense for that one project."
  (and my/gitlab-project-id
       (equal (format "%s" project-id) (format "%s" my/gitlab-project-id))))

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

(map! :leader
      :prefix "o"
      :desc "GitLab My MRs" "g p" #'my/gitlab-my-merge-requests
      :desc "GitLab My Issues" "g a" #'my/gitlab-my-issues)

;; :: ------------------------------------------------------------
;; :: Editing an issue's labels from its org file
;; :: ------------------------------------------------------------
;;
;; :: `my/gitlab-issue-toggle-label' (SPC o g L) works inside any issue file in
;; :: `my/gitlab-issues-dir'.  It offers every label the project can use --
;; :: project *and* inherited group labels, rendered in their own colours --
;; :: with the ones already on the issue marked and listed first.  Picking one
;; :: toggles it: applied labels come off, unapplied ones go on.
;; ::
;; :: Scoped labels (`stage::refine') need no special handling -- GitLab drops
;; :: the previous label in a scope when a new one is added, so picking
;; :: `stage::dev_review' replaces `stage::refine' server-side.

(defvar my/gitlab-labels-max-pages 10
  "Safety cap on how many pages of labels `my/gitlab--fetch-all-labels' walks.")

(defun my/gitlab-issue--current-id ()
  "Return the issue IID for the current buffer's file.
Signals an error unless the buffer visits a `PROJECT#<ID> - ....org' file
inside `my/gitlab-issues-dir', the same guard the other issue-file
commands use."
  (let* ((file (buffer-file-name))
         (issues-dir (my/gitlab-issues-dir))
         (filename (and file (file-name-nondirectory file))))
    (unless (and file (string-prefix-p issues-dir (expand-file-name file)))
      (user-error "This command only works on files in %s" issues-dir))
    (unless (string-match (format "^%s#\\([0-9]+\\)" (regexp-quote my/gitlab-project-name))
                          filename)
      (user-error "Filename must start with %s#<ID>" my/gitlab-project-name))
    (match-string 1 filename)))

(defun my/gitlab--label-face (label)
  "Return a face plist painting LABEL in its own GitLab colours.
Falls back to no styling when the API gives no usable hex colour."
  (let ((bg (gethash "color" label))
        (fg (gethash "text_color" label)))
    (if (and (stringp bg) (string-match-p "\\`#[0-9a-fA-F]\\{6\\}\\'" bg))
        (list :background bg
              :foreground (if (and (stringp fg)
                                   (string-match-p "\\`#[0-9a-fA-F]\\{6\\}\\'" fg))
                              fg
                            "#ffffff"))
      'default)))

(defun my/gitlab--fetch-all-labels (callback &optional page acc)
  "Collect every label available to the project, then call CALLBACK with them.
Walks pagination -- the project inherits group labels, so one page is not
enough -- stopping at `my/gitlab-labels-max-pages'."
  (let ((page (or page 1)))
    (my/gitlab--api-get-async
     (format "projects/%s/labels" (url-hexify-string my/gitlab-project-id))
     (format "per_page=100&page=%d&with_counts=false" page)
     (lambda (labels)
       (if (not (and labels (listp labels)))
           (funcall callback acc)
         (let ((all (append acc labels)))
           (if (and (= (length labels) 100) (< page my/gitlab-labels-max-pages))
               (my/gitlab--fetch-all-labels callback (1+ page) all)
             (funcall callback all))))))))

(defun my/gitlab--label-candidates (labels current)
  "Return an alist of (DISPLAY . NAME) for LABELS, CURRENT ones marked and first.
DISPLAY carries the label's colours as text properties, so the completion
UI shows the same chips GitLab does."
  (let (on off)
    (dolist (label labels)
      (unless (my/gitlab--truthy (gethash "archived" label))
        (let* ((name (gethash "name" label))
               (applied (member name current))
               (display (concat (if applied "✓ " "  ")
                                (propertize (format " %s " name)
                                            'face (my/gitlab--label-face label)))))
          (if applied (push (cons display name) on) (push (cons display name) off)))))
    (append (nreverse on) (nreverse off))))

(defun my/gitlab-issue--update-labels-line (labels)
  "Rewrite the `- *Labels:*' line of the current buffer to LABELS.
Removes the line when LABELS is empty; inserts one after Author (or URL)
when the issue had no labels at the time the file was written."
  (save-excursion
    (let ((text (and labels
                     (format "- *Labels:* %s\n" (mapconcat #'identity labels ", ")))))
      (goto-char (point-min))
      (cond
       ((re-search-forward "^- \\*Labels:\\* .*\n" nil t)
        ;; :: LITERAL, so `\\' and `&' inside a label name stay literal
        (replace-match (or text "") t t))
       ((null text) nil)
       (t (goto-char (point-min))
          (when (or (re-search-forward "^- \\*Author:\\* .*\n" nil t)
                    (progn (goto-char (point-min))
                           (re-search-forward "^- \\*URL:\\* .*\n" nil t)))
            (insert text)))))))

(defun my/gitlab-issue--apply-label (issue-id name addp buffer)
  "Add (ADDP non-nil) or remove label NAME on ISSUE-ID, then refresh BUFFER."
  (my/gitlab--api-request-async
   "PUT"
   (format "projects/%s/issues/%s"
           (url-hexify-string my/gitlab-project-id) issue-id)
   (format "%s=%s" (if addp "add_labels" "remove_labels") (url-hexify-string name))
   (lambda (issue)
     (cond
      ((or (null issue) (null (gethash "iid" issue)))
       (message "Could not %s label %s%s"
                (if addp "add" "remove") name
                (if (and issue (gethash "message" issue))
                    (format ": %s" (gethash "message" issue)) "")))
      ((not (buffer-live-p buffer))
       (message "Label %s %s, but the buffer is gone" name (if addp "added" "removed")))
      (t
       (let ((labels (gethash "labels" issue)))
         (with-current-buffer buffer
           (my/gitlab-issue--update-labels-line labels)
           (when (buffer-file-name) (save-buffer)))
         (message "%s %s — now: %s"
                  (if addp "Added" "Removed") name
                  (if labels (mapconcat #'identity labels ", ") "(none)"))))))))

;;;###autoload
(defun my/gitlab-issue-toggle-label ()
  "Toggle a GitLab label on the issue this buffer is visiting.

Offers every label the project can use -- its own and the ones inherited
from the group -- each rendered in its GitLab colour.  Labels already on
the issue are marked with a check and sorted to the top, so the same
command adds and removes.  The `- *Labels:*' line is rewritten from the
API's response and the file saved, so what you see matches the server.

Scoped labels need no care: picking `stage::dev_review' makes GitLab drop
`stage::refine' on its own."
  (interactive)
  (my/gitlab-check-config)
  (let ((issue-id (my/gitlab-issue--current-id))
        (buffer (current-buffer)))
    (message "Fetching labels...")
    (my/gitlab--fetch-all-labels
     (lambda (labels)
       (if (null labels)
           (message "No labels found for this project")
         (my/gitlab--api-get-async
          (format "projects/%s/issues/%s"
                  (url-hexify-string my/gitlab-project-id) issue-id)
          ""
          (lambda (issue)
            (if (or (null issue) (null (gethash "iid" issue)))
                (message "Could not read issue #%s" issue-id)
              (let* ((current (gethash "labels" issue))
                     (candidates (my/gitlab--label-candidates labels current))
                     (choice (completing-read
                              (format "Label for #%s (%d on, %d available): "
                                      issue-id (length current) (length candidates))
                              (my/gitlab--completion-table candidates) nil t))
                     (name (cdr (assoc choice candidates))))
                (if (null name)
                    (message "No label selected")
                  (my/gitlab-issue--apply-label
                   issue-id name (not (member name current)) buffer))))))))) ))

(map! :leader
      :prefix "o"
      :desc "GitLab Toggle Issue Label" "g L" #'my/gitlab-issue-toggle-label)

(provide 'gitlab)
;;; gitlab.el ends here
