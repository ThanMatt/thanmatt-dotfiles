;;; modules/db-write.el -*- lexical-binding: t; -*-
;; :: Write mode for the read-only psql browser (modules/db-browser.el): edit a
;; :: row, delete rows (vim bindings), all inside an explicit transaction you
;; :: commit or roll back.
;; ::
;; :: Why a live session: Postgres only shows uncommitted changes WITHIN the same
;; :: session, so to `SELECT' and see your own not-yet-committed edits we hold one
;; :: persistent `psql' process per connection with an open BEGIN. Browsing stays
;; :: read-only (one-shot psql with read-only PGOPTIONS); only this path writes,
;; :: and only ever inside a transaction -- nothing is durable until commit.
;; ::
;; :: Loads AFTER db.el / db-browser.el / db-saved.el (see config.el): it reuses
;; :: their connection + credential helpers and the my/sql-result-mode buffers.

(require 'cl-lib)

;; ──────────────────────────────────────────────────────
;; :: Per-connection transaction session
;; ::   conn(string) -> plist(:process PROC :buffer PBUF :writes N)
;; ──────────────────────────────────────────────────────
(defvar my/sql--txn-sessions (make-hash-table :test 'equal)
  ":: live psql transaction sessions, keyed by connection name string")

(defvar-local my/sql--txn-mark nil
  ":: in a session process buffer, where the current call's output begins")

(defun my/sql--txn-active-p (conn)
  ":: non-nil when CONN has a live open-transaction session"
  (let ((s (gethash conn my/sql--txn-sessions)))
    (and s (process-live-p (plist-get s :process)))))

(defun my/sql--txn-raw (conn input)
  ":: send INPUT to CONN's psql process and return the output it produced, using a
   unique `\\echo' sentinel to detect end-of-output (no prompt-regex guessing)."
  (let* ((sess   (gethash conn my/sql--txn-sessions))
         (proc   (and sess (plist-get sess :process)))
         (pbuf   (and sess (plist-get sess :buffer)))
         (marker (format "__SQLDONE_%d__" (random 100000000))))
    (unless (process-live-p proc)
      (error "No live psql session for %s" conn))
    (with-current-buffer pbuf
      (setq-local my/sql--txn-mark (point-max)))
    (process-send-string proc input)
    (process-send-string proc (format "\\echo %s\n" marker))
    (let ((deadline (+ (float-time) 15)))
      (catch 'done
        (while t
          (with-current-buffer pbuf
            (goto-char my/sql--txn-mark)
            (when (re-search-forward (regexp-quote marker) nil t)
              (throw 'done t)))
          (unless (process-live-p proc)
            (error "psql session for %s died: %s" conn
                   (string-trim (with-current-buffer pbuf (buffer-string)))))
          (when (> (float-time) deadline)
            (error "psql session for %s timed out" conn))
          (accept-process-output proc 0.1))))
    (with-current-buffer pbuf
      (goto-char my/sql--txn-mark)
      (let* ((mend (progn (re-search-forward (regexp-quote marker)) (match-beginning 0)))
             (out  (buffer-substring-no-properties my/sql--txn-mark mend)))
        ;; :: trim only surrounding newlines -- never spaces (could be field data)
        (replace-regexp-in-string "\\`[\n\r]+\\|[\n\r]+\\'" "" out)))))

(defun my/sql-txn-begin (conn)
  ":: open a transaction session for CONN: start a persistent psql, configure it
   for machine-readable output, and send BEGIN. Writes go through it from now on."
  (interactive (list (my/sql--current-conn)))
  (when (my/sql--txn-active-p conn)
    (user-error "Transaction already open on %s" conn))
  (my/sql--ensure-connections)
  (let* ((entry (my/sql--conn conn))
         (host  (my/sql--field entry 'sql-server))
         (port  (or (my/sql--field entry 'sql-port) 5432))
         (db    (my/sql--field entry 'sql-database))
         (user  (my/sql--field entry 'sql-user))
         (pass  (my/sql--password host port db user))
         (pbuf  (get-buffer-create (format " *sql-txn:%s*" conn)))
         (process-environment
          (append (when pass (list (concat "PGPASSWORD=" pass)))
                  (list "PAGER=cat")
                  process-environment))
         (proc  (make-process
                 :name (format "sql-txn:%s" conn)
                 :buffer pbuf
                 :command (list "psql" "-h" host "-p" (number-to-string port)
                                "-U" user "-d" db "-w" "-q" "--no-psqlrc")
                 :connection-type 'pipe
                 :coding 'utf-8
                 :noquery t)))
    (puthash conn (list :process proc :buffer pbuf :writes 0) my/sql--txn-sessions)
    (condition-case err
        (my/sql--txn-raw conn
          (concat "\\set ON_ERROR_ROLLBACK interactive\n"
                  "\\pset format csv\n"
                  (format "\\pset null '%s'\n" my/sql--null-sentinel)
                  "\\pset footer off\n"
                  "\\pset pager off\n"
                  "BEGIN;\n"))
      (error (my/sql--txn-teardown conn) (signal (car err) (cdr err))))
    (when (called-interactively-p 'interactive)
      (message "Transaction OPEN on %s" conn))
    conn))

(defun my/sql--txn-teardown (conn)
  ":: quit + kill CONN's psql process and forget the session (no commit/rollback)"
  (let* ((sess (gethash conn my/sql--txn-sessions))
         (proc (and sess (plist-get sess :process)))
         (pbuf (and sess (plist-get sess :buffer))))
    (when (process-live-p proc)
      (ignore-errors (process-send-string proc "\\q\n"))
      (ignore-errors (delete-process proc)))
    (when (buffer-live-p pbuf) (kill-buffer pbuf))
    (remhash conn my/sql--txn-sessions)))

(defun my/sql--write (conn sql)
  ":: run a write SQL inside CONN's open txn; raise on ERROR, bump the write count"
  (let ((out (my/sql--txn-raw conn (concat (string-trim-right sql ";") ";\n"))))
    (when (string-match-p "ERROR:" out)
      (user-error "%s" (string-trim out)))
    (let ((s (gethash conn my/sql--txn-sessions)))
      (puthash conn (plist-put s :writes (1+ (or (plist-get s :writes) 0)))
               my/sql--txn-sessions))
    out))

(defun my/sql--ensure-txn (conn)
  ":: auto-open a transaction on first write (every change is a txn, for safety)"
  (unless (my/sql--txn-active-p conn)
    (my/sql-txn-begin conn)
    (message "Started transaction on %s" conn)))

;; ──────────────────────────────────────────────────────
;; :: Commit / rollback -- end the transaction, then refresh its result buffers
;; ──────────────────────────────────────────────────────
(defun my/sql--result-buffers-for (conn)
  ":: all my/sql-result-mode buffers bound to CONN"
  (cl-remove-if-not
   (lambda (b)
     (with-current-buffer b
       (and (derived-mode-p 'my/sql-result-mode)
            (equal my/sql--conn-name conn))))
   (buffer-list)))

(defun my/sql--rerender-conn (conn)
  ":: re-render every result buffer for CONN (drops the TXN banner, shows db state)"
  (dolist (b (my/sql--result-buffers-for conn))
    (with-current-buffer b (ignore-errors (my/sql--render)))))

(defun my/sql-txn-commit (conn)
  ":: COMMIT CONN's transaction (after confirmation) and refresh its buffers"
  (interactive (list (my/sql--current-conn)))
  (unless (my/sql--txn-active-p conn)
    (user-error "No open transaction on %s" conn))
  (let ((n (or (plist-get (gethash conn my/sql--txn-sessions) :writes) 0)))
    (when (yes-or-no-p (format "Commit %d change(s) on %s? " n conn))
      (my/sql--txn-raw conn "COMMIT;\n")
      (my/sql--txn-teardown conn)
      (my/sql--rerender-conn conn)
      (message "Committed %d change(s) on %s" n conn))))

(defun my/sql-txn-rollback (conn)
  ":: ROLLBACK CONN's transaction (after confirmation) and refresh its buffers"
  (interactive (list (my/sql--current-conn)))
  (unless (my/sql--txn-active-p conn)
    (user-error "No open transaction on %s" conn))
  (let ((n (or (plist-get (gethash conn my/sql--txn-sessions) :writes) 0)))
    (when (yes-or-no-p (format "Roll back %d change(s) on %s? " n conn))
      (my/sql--txn-raw conn "ROLLBACK;\n")
      (my/sql--txn-teardown conn)
      (my/sql--rerender-conn conn)
      (message "Rolled back %d change(s) on %s" n conn))))

;; :: `*-here' = act on the current result buffer's connection
(defun my/sql-txn-commit-here ()   (interactive) (my/sql-txn-commit   my/sql--conn-name))
(defun my/sql-txn-rollback-here () (interactive) (my/sql-txn-rollback my/sql--conn-name))
(defun my/sql-txn-begin-here ()
  (interactive)
  (my/sql-txn-begin my/sql--conn-name)
  (my/sql--render)
  (message "Transaction OPEN on %s" my/sql--conn-name))

;; ──────────────────────────────────────────────────────
;; :: Cleanup -- never leave a dangling open transaction / row locks
;; ──────────────────────────────────────────────────────
(defun my/sql--maybe-cleanup-on-kill ()
  ":: rolling back when the LAST result buffer for an open txn's connection is killed"
  (when (and (derived-mode-p 'my/sql-result-mode)
             my/sql--conn-name
             (my/sql--txn-active-p my/sql--conn-name)
             (null (cl-remove (current-buffer)
                              (my/sql--result-buffers-for my/sql--conn-name))))
    (ignore-errors (my/sql--txn-raw my/sql--conn-name "ROLLBACK;\n"))
    (my/sql--txn-teardown my/sql--conn-name)
    (message "Rolled back open transaction on %s (buffer closed)" my/sql--conn-name)))

(add-hook 'kill-buffer-hook #'my/sql--maybe-cleanup-on-kill)

(defun my/sql--cleanup-all-txn ()
  ":: roll back + tear down every open session (on Emacs exit)"
  (let (conns)
    (maphash (lambda (k _) (push k conns)) my/sql--txn-sessions)
    (dolist (conn conns)
      (ignore-errors (my/sql--txn-raw conn "ROLLBACK;\n"))
      (my/sql--txn-teardown conn))))

(add-hook 'kill-emacs-hook #'my/sql--cleanup-all-txn)

;; ──────────────────────────────────────────────────────
;; :: SQL literal helpers -- the user-facing token NULL <-> SQL NULL
;; ──────────────────────────────────────────────────────
(defun my/sql--sql-literal (val &optional col)
  ":: SQL literal for VAL. \"NULL\" (or the null sentinel) -> NULL; `ctid' is cast"
  (cond
   ((or (null val)
        (string= val "NULL")
        (string= val my/sql--null-sentinel)) "NULL")
   ((equal col "ctid")
    (format "'%s'::tid" (replace-regexp-in-string "'" "''" val)))
   (t (format "'%s'" (replace-regexp-in-string "'" "''" val)))))

(defun my/sql--row-predicate (pk-alist)
  ":: `(col = val AND ...)' identifying exactly one row from its pk alist"
  (concat "("
          (mapconcat (lambda (kv)
                       (format "%s = %s" (car kv) (my/sql--sql-literal (cdr kv) (car kv))))
                     pk-alist " AND ")
          ")"))

(defun my/sql--pk-desc (pk)
  ":: human label for a pk alist, e.g. \"id=4\""
  (mapconcat (lambda (kv)
               (format "%s=%s" (car kv) (my/sql--cell-display (cdr kv))))
             pk ", "))

;; ──────────────────────────────────────────────────────
;; :: Delete rows -- vim bindings (`dd', visual `d') + y/n confirmation
;; ──────────────────────────────────────────────────────
(defun my/sql--assert-table-buffer ()
  ":: error unless point is in an editable table browse buffer"
  (unless (and (derived-mode-p 'my/sql-result-mode)
               my/sql--table (not my/sql--raw-sql))
    (user-error "Editing only works in a table browse buffer")))

(defun my/sql-delete-row ()
  ":: delete the row under point (within a transaction) after a y/n confirm"
  (interactive)
  (my/sql--assert-table-buffer)
  (let ((pk (get-text-property (point) 'my/sql-pk)))
    (unless pk (user-error "No row under point (table needs a primary key)"))
    (when (y-or-n-p (format "Delete row %s from %s? " (my/sql--pk-desc pk) my/sql--table))
      (my/sql--ensure-txn my/sql--conn-name)
      (my/sql--write my/sql--conn-name
                     (format "DELETE FROM %s WHERE %s;"
                             my/sql--table (my/sql--row-predicate pk)))
      (my/sql--render)
      (message "Deleted (uncommitted).  , c commit   , k rollback"))))

(defun my/sql-delete-rows (beg end)
  ":: delete every row in the visual selection (one DELETE, one confirm)"
  (interactive "r")
  (my/sql--assert-table-buffer)
  (let ((pks '()))
    (save-excursion
      (goto-char beg)
      (while (< (point) end)
        (let ((pk (get-text-property (point) 'my/sql-pk)))
          (when pk (cl-pushnew pk pks :test #'equal)))
        (forward-line 1)))
    (when (fboundp 'evil-normal-state) (evil-normal-state))
    (unless pks (user-error "No rows selected"))
    (when (y-or-n-p (format "Delete %d row(s) from %s? " (length pks) my/sql--table))
      (my/sql--ensure-txn my/sql--conn-name)
      (my/sql--write my/sql--conn-name
                     (format "DELETE FROM %s WHERE %s;"
                             my/sql--table
                             (mapconcat #'my/sql--row-predicate (nreverse pks) " OR ")))
      (my/sql--render)
      (message "Deleted %d row(s) (uncommitted).  , c commit   , k rollback"
               (length pks)))))

;; ──────────────────────────────────────────────────────
;; :: Edit a row -- form buffer, read-only labels, editable values, evil-friendly
;; ──────────────────────────────────────────────────────
(defvar-local my/sql--edit-conn nil)
(defvar-local my/sql--edit-table nil)
(defvar-local my/sql--edit-pk nil)
(defvar-local my/sql--edit-source nil)
(defvar-local my/sql--edit-fields nil
  ":: list of plists (:col :start :orig). Each value lives on its own line, so the
   value region is :start -> end-of-line (no end marker needed; the trailing
   newline is read-only, so a value can't span lines).")
(defvar-local my/sql--edit-kind 'update
  ":: `update' (edit the row at my/sql--edit-pk) or `insert' (new row, no pk)")

(define-derived-mode my/sql-edit-mode fundamental-mode "DB-Edit"
  ":: form buffer to edit one db row. Labels are read-only; only values are
   editable. Plain buffer, so evil/vim navigation works normally."
  (setq-local truncate-lines nil))

(defun my/sql--ro (s &optional face)
  ":: read-only, non-sticky structural text for the form (labels, newlines)"
  (propertize s 'read-only t 'rear-nonsticky t 'face face))

(defun my/sql--edit-render (row)
  ":: draw the form for ROW (alist col->raw) and record the editable field markers"
  (let* ((inhibit-read-only t)
         (width (apply #'max 1 (mapcar (lambda (kv) (length (car kv))) row))))
    (erase-buffer)
    (insert (my/sql--ro
             (if (eq my/sql--edit-kind 'insert)
                 (format (concat "# insert into %s/%s   (empty = default, NULL = null)"
                                 "   C-c C-c apply   C-c C-k cancel\n\n")
                         my/sql--edit-conn my/sql--edit-table)
               (format "# edit %s/%s  [%s]   C-c C-c apply   C-c C-k cancel\n\n"
                       my/sql--edit-conn my/sql--edit-table
                       (my/sql--pk-desc my/sql--edit-pk)))
             'font-lock-comment-face))
    (setq my/sql--edit-fields nil)
    (dolist (kv row)
      (let* ((col     (car kv))
             (raw     (cdr kv))
             (display (if (string= raw my/sql--null-sentinel) "NULL" raw))
             start)
        ;; :: Emacs `format' has no C-style %-*s (dynamic width) -- bake WIDTH in
        (insert (my/sql--ro (format (format "%%-%ds : " width) col)
                            'font-lock-keyword-face))
        (setq start (point-marker))
        (set-marker-insertion-type start nil)  ;; :: stays put as later fields are inserted
        (insert display)
        (insert (my/sql--ro "\n"))             ;; :: read-only -> value can't span lines
        (push (list :col col :start start :orig raw) my/sql--edit-fields)))
    (setq my/sql--edit-fields (nreverse my/sql--edit-fields))
    (when my/sql--edit-fields
      (goto-char (plist-get (car my/sql--edit-fields) :start)))))

(defun my/sql-edit-row ()
  ":: open a form to edit the row under point (auto-starts a transaction)"
  (interactive)
  (my/sql--assert-table-buffer)
  (let ((pk     (get-text-property (point) 'my/sql-pk))
        (row    (get-text-property (point) 'my/sql-row))
        (conn   my/sql--conn-name)
        (table  my/sql--table)
        (source (current-buffer)))
    (unless pk (user-error "No editable row under point (table needs a primary key)"))
    ;; :: don't open a transaction just to view the form -- edit-commit starts one
    ;; :: only if/when there are actual changes to write.
    (let ((buf (get-buffer-create
                (format "*edit %s/%s [%s]*" conn table (my/sql--pk-desc pk)))))
      (with-current-buffer buf
        (my/sql-edit-mode)
        (setq my/sql--edit-conn conn my/sql--edit-table table
              my/sql--edit-pk pk my/sql--edit-source source
              my/sql--edit-kind 'update)
        (my/sql--edit-render row))
      (when (fboundp 'persp-add-buffer) (persp-add-buffer buf))
      (select-window (display-buffer buf)))))

(defun my/sql--table-columns (conn table)
  ":: ordered column names of TABLE (schema-qualified or bare) on CONN"
  (let* ((parts  (split-string table "\\."))
         (schema (if (cdr parts) (car parts) "public"))
         (name   (or (cadr parts) (car parts)))
         (sql    (format (concat "SELECT column_name FROM information_schema.columns "
                                 "WHERE table_schema = '%s' AND table_name = '%s' "
                                 "ORDER BY ordinal_position;")
                         schema name))
         (res    (my/sql--psql conn sql t)))
    (and (zerop (car res))
         (split-string (cdr res) "\n" t "[ \t\r]+"))))

(defun my/sql-insert-row ()
  ":: open a blank form to insert a new row (empty field = column default)"
  (interactive)
  (my/sql--assert-table-buffer)
  (let* ((conn   my/sql--conn-name)
         (table  my/sql--table)
         (cols   (my/sql--table-columns conn table))
         (row    (mapcar (lambda (c) (cons c "")) cols))   ;; :: all columns blank
         (source (current-buffer))
         (buf    (get-buffer-create (format "*insert %s/%s*" conn table))))
    (unless cols (user-error "Could not read columns for %s" table))
    (with-current-buffer buf
      (my/sql-edit-mode)
      (setq my/sql--edit-conn conn my/sql--edit-table table
            my/sql--edit-pk nil my/sql--edit-source source
            my/sql--edit-kind 'insert)
      (my/sql--edit-render row))
    (when (fboundp 'persp-add-buffer) (persp-add-buffer buf))
    (select-window (display-buffer buf))))

(defun my/sql--edit-field-value (f)
  ":: current text of field F -- from its :start marker to end of that line"
  (let ((start (plist-get f :start)))
    (buffer-substring-no-properties
     start (save-excursion (goto-char start) (line-end-position)))))

(defun my/sql--finish-edit (source verb)
  ":: refresh SOURCE, close the form (restoring window layout), report VERB"
  (when (buffer-live-p source)
    (with-current-buffer source (my/sql--render)))
  ;; :: kill the form AND restore the window layout (delete the popped window
  ;; :: rather than leaving a 2nd copy of the table in it)
  (quit-window t)
  (message "%s (uncommitted).  , c commit   , k rollback" verb))

(defun my/sql-edit-commit ()
  ":: apply the form -- UPDATE (changed fields) or INSERT (non-empty fields)"
  (interactive)
  (if (eq my/sql--edit-kind 'insert)
      (my/sql--insert-commit)
    (my/sql--update-commit)))

(defun my/sql--update-commit ()
  ":: UPDATE only the changed fields, then refresh + close"
  (let ((conn my/sql--edit-conn) (table my/sql--edit-table)
        (pk my/sql--edit-pk) (source my/sql--edit-source) (sets '()))
    (dolist (f my/sql--edit-fields)
      (let* ((col   (plist-get f :col))
             (new   (my/sql--edit-field-value f))
             (orig  (plist-get f :orig))
             ;; :: canonicalise the user token NULL back to the sentinel for compare
             (canon (if (string= new "NULL") my/sql--null-sentinel new)))
        (unless (string= canon orig)
          (push (format "%s = %s" col (my/sql--sql-literal new col)) sets))))
    (if (null sets)
        (progn (message "No changes") (my/sql-edit-abort))
      (my/sql--ensure-txn conn)
      (my/sql--write conn (format "UPDATE %s SET %s WHERE %s;"
                                  table (mapconcat #'identity (nreverse sets) ", ")
                                  (my/sql--row-predicate pk)))
      (my/sql--finish-edit source "Updated"))))

(defun my/sql--insert-commit ()
  ":: INSERT the non-empty fields (empty field -> column default), then refresh + close"
  (let ((conn my/sql--edit-conn) (table my/sql--edit-table)
        (source my/sql--edit-source) (cols '()) (vals '()))
    (dolist (f my/sql--edit-fields)
      (let ((col (plist-get f :col))
            (new (my/sql--edit-field-value f)))
        (unless (string= new "")          ;; :: blank -> omit so the DEFAULT applies
          (push col cols)
          (push (my/sql--sql-literal new col) vals))))
    (my/sql--ensure-txn conn)
    (my/sql--write conn
                   (if cols
                       (format "INSERT INTO %s (%s) VALUES (%s);"
                               table
                               (mapconcat #'identity (nreverse cols) ", ")
                               (mapconcat #'identity (nreverse vals) ", "))
                     (format "INSERT INTO %s DEFAULT VALUES;" table)))
    (my/sql--finish-edit source "Inserted")))

(defun my/sql-edit-abort ()
  ":: discard the edit form without writing (kill it + restore the window layout)"
  (interactive)
  (quit-window t))

(map! :map my/sql-edit-mode-map
      :n "q" #'my/sql-edit-abort
      "C-c C-c" #'my/sql-edit-commit
      "C-c C-k" #'my/sql-edit-abort)
