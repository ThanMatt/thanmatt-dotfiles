;;; modules/db.el -*- lexical-binding: t; -*-
;; :: connections, secrets, query templates -- read-only Postgres workflow.
;; :: sql-mode is built into Emacs (no Doom module), so require it directly.

(require 'sql)
(require 'auth-source)

;; ──────────────────────────────────────────────────────
;; :: Secrets / source of truth -- ~/.authinfo.gpg.
;; :: sql-mode does NOT read ~/.authinfo.gpg by default (it uses sql-wallet.gpg),
;; :: so point it there explicitly. Entries use a server/database host key,
;; :: with an optional `name' token for a friendly display alias:
;; ::   machine localhost/bukasstore port 5432 login bukasstore_user \
;; ::     password SECRET name bukasstore-db
;; ──────────────────────────────────────────────────────
(setq sql-password-wallet '("~/.authinfo.gpg"))

;; ──────────────────────────────────────────────────────
;; :: Connection presets -- derived from the wallet (one source of truth).
;; :: Add a DB by editing only ~/.authinfo.gpg; no preset list to maintain.
;; ──────────────────────────────────────────────────────
(defun my/sql--connections-from-authinfo ()
  ":: build sql-connection-alist from ~/.authinfo.gpg entries whose machine is
   host/db. non-db secrets (email, tokens, bare-host entries) are skipped via the
   `/' heuristic. Label prefers the optional `name' token, else falls back to host/db."
  (let (alist)
    (dolist (e (auth-source-netrc-parse-all
                (expand-file-name (car sql-password-wallet))))
      (let ((machine (cdr (assoc "machine" e))))
        (when (and machine (string-match "\\`\\([^/]+\\)/\\(.+\\)\\'" machine))
          (let ((server (match-string 1 machine))
                (db     (match-string 2 machine))
                (port   (cdr (assoc "port"  e)))
                (user   (cdr (assoc "login" e)))
                (alias  (cdr (assoc "name"  e))))   ;; :: optional friendly label
            (push (list (intern (or alias machine)) ;; :: alias if present, else host/db
                        (list 'sql-product ''postgres)
                        (list 'sql-server server)
                        (list 'sql-port (if port (string-to-number port) 5432))
                        (list 'sql-database db)      ;; :: real db name, always
                        (list 'sql-user user))
                  alist)))))
    (nreverse alist)))

(defun my/sql-reload-connections ()
  ":: refresh presets from the wallet AND flush the table cache -- a full reset,
   so a stale (e.g. pre-tunnel) table list can't linger after editing the wallet"
  (interactive)
  (setq sql-connection-alist (my/sql--connections-from-authinfo))
  (when (boundp 'my/sql--table-cache) (clrhash my/sql--table-cache))
  (message "Loaded %d db connection(s)" (length sql-connection-alist)))

(defun my/sql--ensure-connections ()
  ":: populate presets on first use, so we only hit the gpg prompt when needed"
  (unless sql-connection-alist (my/sql-reload-connections)))

;; :: make the built-in connect picker (SPC d s c) populate from the wallet too
(advice-add 'sql-connect :before (lambda (&rest _) (my/sql--ensure-connections)))

;; ──────────────────────────────────────────────────────
;; :: Query templates -- add as many as you need
;; ──────────────────────────────────────────────────────
(defvar my/sql-templates
  '(("select all"          . "SELECT * FROM <param:table>;")
    ("count rows"          . "SELECT COUNT(*) FROM <param:table>;")
    ("select where"        . "SELECT * FROM <param:table> WHERE <param:column> = '<param:value>';")
    ("select limit"        . "SELECT * FROM <param:table> LIMIT <param:limit>;")
    ("describe table"      . "\\d <param:table>")
    ("list tables"         . "\\dt")
    ("list columns"        . "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = '<param:table>';")
    ("show indexes"        . "SELECT indexname, indexdef FROM pg_indexes WHERE tablename = '<param:table>';"))
  ":: alist of named sql query templates with <param:name> placeholders")

(defun my/sql--fill-template (name)
  ":: fill a template's params interactively, return the final query string"
  (let* ((template (cdr (assoc name my/sql-templates)))
         (query template)
         (param-regex "<param:\\([^>]+\\)>"))
    (while (string-match param-regex query)
      (let* ((param-name (match-string 1 query))
             (value (read-string (format "%s: " param-name))))
        (setq query (replace-match value t t query))))
    query))

(defun my/sql-run-template ()
  ":: pick a query template, fill params interactively, send to active sql session"
  (interactive)
  (let* ((name (completing-read "Template: " my/sql-templates nil t)))
    (sql-send-string (my/sql--fill-template name))))

(defun my/sql-preview-template ()
  ":: fill a query template and copy to clipboard instead of auto-sending"
  (interactive)
  (let* ((name (completing-read "Template: " my/sql-templates nil t))
         (query (my/sql--fill-template name)))
    (kill-new query)
    (message "Copied: %s" query)))

;; ──────────────────────────────────────────────────────
;; :: Free-form scratch buffer
;; ──────────────────────────────────────────────────────
(defun my/sql-scratch ()
  ":: open a free-form sql-mode scratch buffer in another window"
  (interactive)
  (let ((buf (get-buffer-create "*sql-scratch*")))
    (with-current-buffer buf (sql-mode))
    (switch-to-buffer-other-window buf)))
