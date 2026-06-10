;;; modules/db-browser.el -*- lexical-binding: t; -*-
;; :: read-only table browser over psql. Pick a DB -> fuzzy-pick a table ->
;; :: view rows in an evil-navigable buffer -> filter (WHERE) / limit in place.
;; :: Reuses sql-connection-alist (modules/db.el) + ~/.authinfo.gpg for creds.
;; :: Read-only is enforced server-side via PGOPTIONS.

(require 'auth-source)

;; ──────────────────────────────────────────────────────
;; :: Connection + credential helpers (reuse sql-connection-alist)
;; ──────────────────────────────────────────────────────
(defun my/sql--conn (name)
  ":: connection-alist entry for NAME (string or symbol)"
  (assq (if (stringp name) (intern name) name) sql-connection-alist))

(defun my/sql--field (entry field)
  ":: pull FIELD (e.g. 'sql-server) out of a connection entry"
  (cadr (assq field (cdr entry))))

(defun my/sql--password (host port db user)
  ":: fetch password from the authinfo wallet (host key is server/database)"
  (let* ((found (car (auth-source-search :host (concat host "/" db)
                                         :port (number-to-string port)
                                         :user user :max 1)))
         (secret (and found (plist-get found :secret))))
    (when secret (if (functionp secret) (funcall secret) secret))))

;; ──────────────────────────────────────────────────────
;; :: Run psql, read-only enforced at the session level
;; ──────────────────────────────────────────────────────
(defun my/sql--psql (conn-name sql &optional tuples-only)
  ":: run SQL against CONN-NAME via psql, return stdout as a string"
  (let* ((entry (my/sql--conn conn-name))
         (host  (my/sql--field entry 'sql-server))
         (port  (or (my/sql--field entry 'sql-port) 5432))
         (db    (my/sql--field entry 'sql-database))
         (user  (my/sql--field entry 'sql-user))
         (pass  (my/sql--password host port db user))
         (process-environment
          (append (list "PGOPTIONS=-c default_transaction_read_only=on")
                  (when pass (list (concat "PGPASSWORD=" pass)))
                  process-environment))
         (args  (append (list "-h" host "-p" (number-to-string port)
                              "-U" user "-d" db "-w")
                        (when tuples-only (list "-t" "-A"))
                        (list "-c" sql))))
    (with-output-to-string
      (apply #'call-process "psql" nil standard-output nil args))))

;; ──────────────────────────────────────────────────────
;; :: Table list with cache (invalidate via refresh)
;; ──────────────────────────────────────────────────────
(defvar my/sql--table-cache (make-hash-table :test 'equal)
  ":: cached table names, keyed by connection name string")

(defun my/sql--tables (conn-name &optional refresh)
  ":: schema-qualified tables for CONN-NAME; cached unless REFRESH"
  (let ((key (format "%s" conn-name)))
    (when refresh (remhash key my/sql--table-cache))
    (or (gethash key my/sql--table-cache)
        (puthash key
                 (split-string
                  (my/sql--psql conn-name
                    (concat "SELECT schemaname||'.'||tablename "
                            "FROM pg_catalog.pg_tables "
                            "WHERE schemaname NOT IN ('pg_catalog','information_schema') "
                            "ORDER BY 1;")
                    t)
                  "\n" t "[ \t\r]+")
                 my/sql--table-cache))))

;; ──────────────────────────────────────────────────────
;; :: Result buffer: read-only, evil-navigable, refresh-in-place
;; ──────────────────────────────────────────────────────
(defvar-local my/sql--conn-name nil)
(defvar-local my/sql--table nil)
(defvar-local my/sql--where nil)
(defvar-local my/sql--limit 100)

(define-derived-mode my/sql-result-mode special-mode "DB-Result"
  ":: read-only db result viewer"
  (setq-local truncate-lines t))

;; :: special-mode lands in evil `motion' state, where `,' is repeat-find-char,
;; :: not the localleader. Force normal state so `, f' etc. work as documented.
(when (fboundp 'evil-set-initial-state)
  (evil-set-initial-state 'my/sql-result-mode 'normal))

(defun my/sql--buffer-name ()
  ":: buffer title from current state -- table + active filter. No earmuffs, so it
   shows up as a first-class buffer in `SPC ,' / the workspace switcher."
  (format "DB %s/%s%s"
          my/sql--conn-name my/sql--table
          (if (and my/sql--where (not (string-empty-p my/sql--where)))
              (format " [%s]" my/sql--where) "")))

(defun my/sql--render ()
  ":: rebuild the query from buffer-local state and redraw in place"
  (let* ((where (if (and my/sql--where (not (string-empty-p my/sql--where)))
                    (concat " WHERE " my/sql--where) ""))
         (limit (if my/sql--limit (format " LIMIT %d" my/sql--limit) ""))
         (sql   (format "SELECT * FROM %s%s%s;" my/sql--table where limit))
         (out   (my/sql--psql my/sql--conn-name sql))
         (inhibit-read-only t))
    (rename-buffer (my/sql--buffer-name) t)  ;; :: keep title in sync with the query
    (erase-buffer)
    (insert (format "-- %s  @ %s\n-- %s\n\n" my/sql--table my/sql--conn-name sql))
    (insert out)
    (goto-char (point-min))))

;; ──────────────────────────────────────────────────────
;; :: Commands
;; ──────────────────────────────────────────────────────
(defun my/sql-browse (&optional refresh)
  ":: pick a db + table, open a read-only result buffer (C-u refreshes table cache)"
  (interactive "P")
  (my/sql--ensure-connections)
  (let* ((conn (completing-read "DB: "
                 (mapcar (lambda (c) (symbol-name (car c))) sql-connection-alist) nil t))
         (table (completing-read "Table: " (my/sql--tables conn refresh) nil t))
         (buf (get-buffer-create (format "DB %s/%s" conn table))))
    (with-current-buffer buf
      (my/sql-result-mode)
      (setq my/sql--conn-name conn my/sql--table table
            my/sql--where nil my/sql--limit 100)
      (my/sql--render))
    ;; :: register in the current Doom workspace so it shows in `SPC ,'
    (when (fboundp 'persp-add-buffer) (persp-add-buffer buf))
    (switch-to-buffer buf)))

(defun my/sql-where ()
  ":: set/edit the WHERE clause (blank = unfiltered) and re-run"
  (interactive)
  (setq my/sql--where (read-string "WHERE: " my/sql--where))
  (my/sql--render))

(defun my/sql-limit (n)
  ":: set the row LIMIT (0 = no limit) and re-run"
  (interactive "nLIMIT (0 = no limit): ")
  (setq my/sql--limit (if (<= n 0) nil n))
  (my/sql--render))

(defun my/sql-refresh ()
  ":: re-run the current query"
  (interactive)
  (my/sql--render))

(defun my/sql-refresh-tables ()
  ":: invalidate + rebuild this connection's table cache"
  (interactive)
  (my/sql--tables my/sql--conn-name t)
  (message "Refreshed table list for %s" my/sql--conn-name))

(defun my/sql-switch-table ()
  ":: switch this buffer to another table (resets filter)"
  (interactive)
  (let ((table (completing-read "Table: " (my/sql--tables my/sql--conn-name) nil t)))
    (setq my/sql--table table my/sql--where nil)
    (my/sql--render)))  ;; :: render renames the buffer to match the new table

;; ──────────────────────────────────────────────────────
;; :: In-buffer keys via localleader -- leaves hjkl/search motions untouched
;; ──────────────────────────────────────────────────────
(map! :map my/sql-result-mode-map
      :n "q" #'quit-window
      :localleader
      :desc "Filter (WHERE)" "f" #'my/sql-where
      :desc "Set row LIMIT"  "l" #'my/sql-limit
      :desc "Re-run query"   "r" #'my/sql-refresh
      :desc "Refresh tables" "R" #'my/sql-refresh-tables
      :desc "Switch table"   "t" #'my/sql-switch-table)
