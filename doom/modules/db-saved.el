;;; modules/db-saved.el -*- lexical-binding: t; -*-
;; :: Save SQL queries to a persisted store and retrieve them with a dimmed
;; :: inline preview. A saved query is tagged with the connection it came from
;; :: and can be run against that connection or (with C-u) any other one.
;; :: Builds on the psql result buffer in modules/db-browser.el, so this loads
;; :: AFTER db.el and db-browser.el (see config.el).

;; ──────────────────────────────────────────────────────
;; :: Store -- a single alist sexp on disk, per-machine (not in the repo)
;; ::   NAME(string) -> (:query SQL :conn CONN :saved TIMESTAMP)
;; ──────────────────────────────────────────────────────
(defvar my/sql-saved-file
  (expand-file-name "sql-saved-queries.el"
                    (or (bound-and-true-p doom-data-dir) user-emacs-directory))
  ":: file where saved queries persist (one alist sexp)")

(defvar my/sql-saved-queries nil
  ":: alist NAME -> plist (:query :conn :saved). Loaded lazily from disk.")

(defvar my/sql--saved-loaded nil
  ":: t once we've read the store this session")

(defun my/sql--saved-load ()
  ":: read saved queries from disk once"
  (unless my/sql--saved-loaded
    (when (file-exists-p my/sql-saved-file)
      (with-temp-buffer
        (insert-file-contents my/sql-saved-file)
        (setq my/sql-saved-queries (ignore-errors (read (current-buffer))))))
    (setq my/sql--saved-loaded t)))

(defun my/sql--saved-persist ()
  ":: write saved queries to disk (overwrites)"
  (with-temp-file my/sql-saved-file
    (let ((print-length nil) (print-level nil))
      (prin1 my/sql-saved-queries (current-buffer)))))

;; ──────────────────────────────────────────────────────
;; :: Gather the query + connection to save from the current context
;; ──────────────────────────────────────────────────────
(defun my/sql--current-query ()
  ":: best-guess query to save: active region -> result-buffer SQL -> whole
   sql-mode buffer -> prompt"
  (cond
   ((use-region-p)
    (string-trim (buffer-substring-no-properties (region-beginning) (region-end))))
   ;; :: the exact on-screen query -- selected columns, WHERE, ORDER BY, LIMIT
   ;; :: (or the raw/saved SQL); built by my/sql--current-data-sql in db-browser.el
   ((derived-mode-p 'my/sql-result-mode)
    (string-trim (my/sql--current-data-sql)))
   ((derived-mode-p 'sql-mode)
    (string-trim (buffer-substring-no-properties (point-min) (point-max))))
   (t (read-string "Query: "))))

(defun my/sql--current-conn ()
  ":: connection name for the current buffer, else pick one"
  (or (and (boundp 'my/sql--conn-name) my/sql--conn-name)
      (progn
        (my/sql--ensure-connections)
        (completing-read "Connection: "
                         (mapcar (lambda (c) (symbol-name (car c))) sql-connection-alist)
                         nil t))))

;; ──────────────────────────────────────────────────────
;; :: Commands
;; ──────────────────────────────────────────────────────
(defun my/sql-save-query ()
  ":: save the current query (region / result buffer / sql buffer). Name defaults
   to a timestamp; re-saving an existing name overwrites silently."
  (interactive)
  (my/sql--saved-load)
  (let* ((query   (my/sql--current-query))
         (conn    (my/sql--current-conn))
         (default (format-time-string "%Y-%m-%d %H:%M:%S"))
         (name    (let ((n (read-string (format "Save as (default %s): " default))))
                    (if (string-empty-p n) default n))))
    (setf (alist-get name my/sql-saved-queries nil nil #'equal)
          (list :query query :conn conn
                :saved (format-time-string "%Y-%m-%d %H:%M:%S")))
    (my/sql--saved-persist)
    (message "Saved query %S (%s)" name conn)))

(defun my/sql--saved-annotation (name)
  ":: dimmed `shadow' suffix for a candidate: [conn] one-line query preview"
  (let* ((e    (alist-get name my/sql-saved-queries nil nil #'equal))
         (q    (replace-regexp-in-string "[ \t\n\r]+" " " (or (plist-get e :query) "")))
         (conn (or (plist-get e :conn) "?")))
    (concat (propertize (format "  [%s] " conn) 'face 'font-lock-keyword-face)
            (propertize (truncate-string-to-width q 80 nil nil "…")
                        'face 'shadow))))

(defun my/sql--saved-pick (prompt)
  ":: completing-read over saved names with a shadow query preview annotation"
  (my/sql--saved-load)
  (unless my/sql-saved-queries (user-error "No saved queries yet"))
  (let ((completion-extra-properties
         (list :annotation-function #'my/sql--saved-annotation)))
    (completing-read prompt (mapcar #'car my/sql-saved-queries) nil t)))

(defun my/sql-run-saved (&optional arg)
  ":: pick a saved query (shadow preview) and run it. With C-u, choose a different
   target connection (cross-host)."
  (interactive "P")
  (let* ((name (my/sql--saved-pick "Run saved query: "))
         (e    (alist-get name my/sql-saved-queries nil nil #'equal))
         (sql  (plist-get e :query))
         (conn (if arg
                   (progn
                     (my/sql--ensure-connections)
                     (completing-read "Run on connection: "
                                      (mapcar (lambda (c) (symbol-name (car c)))
                                              sql-connection-alist)
                                      nil t))
                 (plist-get e :conn))))
    (my/sql--open-raw conn sql (format "SQL %s @ %s" name conn))))

(defun my/sql-delete-saved ()
  ":: delete a saved query (no confirmation)"
  (interactive)
  (let ((name (my/sql--saved-pick "Delete saved query: ")))
    (setf (alist-get name my/sql-saved-queries nil 'remove #'equal) nil)
    (my/sql--saved-persist)
    (message "Deleted saved query %S" name)))
