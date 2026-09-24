;;; gitlab/core.el --- GitLab: config, auth, HTTP (sync + async), shared helpers -*- lexical-binding: t; -*-

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

(defun my/gitlab--completion-table (candidates)
  "Return a completion table over CANDIDATES (an alist) that preserves their order."
  (lambda (string pred action)
    (if (eq action 'metadata)
        '(metadata (display-sort-function . identity)
          (cycle-sort-function . identity))
      (complete-with-action action candidates string pred))))

(defadvice! my/url-http-rescan-first-chunk-a (fn st nd length)
  ":: Work around a url-http bug that hangs chunked GitLab responses.
For the first chunk, `url-http-chunked-encoding-after-change-function'
scans from ST, the start of the newly arrived bytes.  When the first
chunk-size line arrives split across two reads, that partial line is never
read again, the parser loses its place and waits for a terminator that
never comes, until the request times out.  Some issue searches, e.g.
\"english\", hit this every time.  Scanning the first chunk from the end
of the headers instead re-reads the partial line once the rest arrives."
  :around #'url-http-chunked-encoding-after-change-function
  ;; :: `url-http-end-of-headers' may be a marker, and url-http's debug
  ;; :: logging formats ST with %d, which rejects markers
  (funcall fn (if (and (= url-http-chunked-counter 0) (not url-http-chunked-start))
                  (if (markerp url-http-end-of-headers)
                      (marker-position url-http-end-of-headers)
                    url-http-end-of-headers)
                st)
           nd length))

(defvar my/gitlab-request-timeout 30
  "Seconds `my/gitlab--api-get-sync' waits for GitLab before giving up.")

(defun my/gitlab--redact (text token)
  "Return TEXT with every occurrence of TOKEN masked."
  (if (and token (not (string-empty-p token)))
      (replace-regexp-in-string (regexp-quote token) "<redacted>" text t t)
    text))

(defun my/gitlab--describe-process (proc)
  "Return a one-line description of the connection process PROC."
  ;; :: Don't add `process-exit-status' here: on a network process still in
  ;; :: the `connect' state it segfaults Emacs 30.2
  (if (not (processp proc))
      "none"
    (format "%s  status=%s" (process-name proc) (process-status proc))))

(defun my/gitlab--retrieve-traced (url timeout)
  "Retrieve URL, waiting up to TIMEOUT seconds, and record what happened.
Honours the dynamically bound `url-request-*' variables.  Unlike
`url-retrieve-synchronously', which returns a bare nil for every kind of
failure, this keeps the evidence.  Return a plist:
  :buffer   the response buffer (partial on a timeout), or nil
  :status   the status plist url.el handed to the callback
  :failure  a one-line reason when no complete response arrived
  :elapsed  seconds spent
  :process  the last seen state of the connection process
  :log      url.el's debug log for the request -- it holds the token!"
  (require 'url)
  (let* ((owned-log (not url-debug))
         (log-start (with-current-buffer (get-buffer-create "*URL-DEBUG*")
                      (copy-marker (point-max))))
         (url-debug t)
         (start (current-time))
         done status response proc-buffer failure process-info log)
    (unwind-protect
        (condition-case err
            (progn
              (setq proc-buffer
                    (url-retrieve url (lambda (s)
                                        (setq status s
                                              response (current-buffer)
                                              done t))
                                  nil t t))
              (while (not (or done failure))
                ;; :: Follow redirects the way `url-retrieve-synchronously' does
                (let ((redirect (and (buffer-live-p proc-buffer)
                                     (buffer-local-value 'url-redirect-buffer proc-buffer))))
                  (when (buffer-live-p redirect)
                    (setq proc-buffer redirect)))
                (let ((proc (get-buffer-process proc-buffer)))
                  (setq process-info (my/gitlab--describe-process proc))
                  (cond
                   ((> (float-time (time-since start)) timeout)
                    (setq failure (format "timed out: no complete response within %ss" timeout)))
                   ((and proc (memq (process-status proc) '(closed exit signal failed)))
                    (setq failure "connection closed before a response arrived"))
                   (t (accept-process-output nil 0.05))))))
          (error (setq failure (format "request could not be sent: %s"
                                       (error-message-string err)))))
      (with-current-buffer (marker-buffer log-start)
        (setq log (buffer-substring-no-properties log-start (point-max)))
        ;; :: The log carries the PRIVATE-TOKEN header in clear text, so
        ;; :: don't leave it in *URL-DEBUG* unless debugging was already on
        (when owned-log
          (let ((inhibit-read-only t))
            (delete-region log-start (point-max)))))
      (set-marker log-start nil))
    (list :buffer (or response proc-buffer)
          :status status
          :failure failure
          :elapsed (float-time (time-since start))
          :process process-info
          :log log)))

(defun my/gitlab--show-failure (reason method url token trace)
  "Show a full report of the failed METHOD request to URL in *GitLab Error*.
REASON is a one-line summary and TRACE the plist from
`my/gitlab--retrieve-traced'.  TOKEN is masked throughout."
  (let* ((response (plist-get trace :buffer))
         (live (buffer-live-p response))
         (report
          (concat
           (format "GitLab request failed: %s\n\n" reason)
           (format "Time:     %s\n" (format-time-string "%F %T %z"))
           (format "Request:  %s %s\n" method url)
           (format "Elapsed:  %.2fs (timeout %ss)\n"
                   (plist-get trace :elapsed) my/gitlab-request-timeout)
           (format "HTTP:     %s\n"
                   (or (and live (buffer-local-value 'url-http-response-status response))
                       "no status line received"))
           (format "Error:    %S\n" (plist-get (plist-get trace :status) :error))
           (format "Process:  %s\n" (plist-get trace :process))
           (format "Emacs:    %s, GnuTLS %s\n" emacs-version
                   (if (gnutls-available-p) "available" "MISSING"))
           "\n* Response received\n\n"
           (if (and live (> (buffer-size response) 0))
               (with-current-buffer response
                 (my/gitlab--decode-body (buffer-substring-no-properties
                                          (point-min) (point-max))))
             "(nothing)")
           "\n\n* url.el debug log\n\n"
           (or (plist-get trace :log) "(empty)"))))
    (with-current-buffer (get-buffer-create "*GitLab Error*")
      (special-mode)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (my/gitlab--redact report token))
        (goto-char (point-min)))
      (display-buffer (current-buffer)))))

(defun my/gitlab--api-get-sync (path query-string)
  "GET /api/v4/PATH?QUERY-STRING synchronously and return parsed JSON.
Objects are hash-tables and arrays are lists.  On a timeout, connection
error, HTTP error or unreadable body, signal an error and show the full
details -- raw response and url.el debug log -- in *GitLab Error*."
  (let* ((token (my/gitlab-get-token))
         (url (format "%s/api/v4/%s?%s" my/gitlab-url path query-string))
         (url-request-method "GET")
         (url-request-extra-headers `(("PRIVATE-TOKEN" . ,token)))
         (trace (my/gitlab--retrieve-traced url my/gitlab-request-timeout))
         (buf (plist-get trace :buffer))
         (reason (or (plist-get trace :failure)
                     (pcase (plist-get (plist-get trace :status) :error)
                       ('nil nil)
                       (`(error http ,code) (format "HTTP %s" code))
                       (`(error connection-failed ,why . ,_)
                        (format "connection failed: %s" (string-trim why)))
                       (other (format "%S" other)))))
         json)
    (unwind-protect
        (progn
          (unless reason
            (condition-case err
                (setq json (with-current-buffer buf (my/gitlab--read-json-body)))
              (error (setq reason (format "unreadable response body: %s"
                                          (error-message-string err))))))
          (when reason
            (my/gitlab--show-failure reason "GET" url token trace)
            (error "GitLab request failed: %s -- full log in *GitLab Error*" reason))
          json)
      (when (buffer-live-p buf)
        (let (kill-buffer-query-functions)
          (kill-buffer buf))))))

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
;; :: Helpers shared by several dashboards / views
;; :: ------------------------------------------------------------

(defun my/gitlab--clean-title (title)
  "Return TITLE with any Draft:/WIP: prefix stripped.
The prefix is redundant -- draft state gets its own column."
  (replace-regexp-in-string "\\`\\(\\[?Draft\\]?\\|\\[?WIP\\]?\\):[ \t]*" ""
                            (or title "")))

(defun my/gitlab--project-of (item)
  "Return ITEM's `group/project' path from its references block."
  (let ((refs (gethash "references" item)))
    (if refs
        (replace-regexp-in-string "[!#].*\\'" "" (or (gethash "full" refs) ""))
      "")))

(defun my/gitlab--own-project-p (project-id)
  "Return non-nil when PROJECT-ID is the project `my/gitlab-project-id' names.
The local issue-file helpers key filenames off `my/gitlab-project-name',
so they only make sense for that one project."
  (and my/gitlab-project-id
       (equal (format "%s" project-id) (format "%s" my/gitlab-project-id))))

;;; core.el ends here
