;;; modules/db-browser.el -*- lexical-binding: t; -*-
;; :: read-only table browser over psql. Pick a DB -> fuzzy-pick a table ->
;; :: view rows in an evil-navigable buffer -> filter (WHERE) / limit in place.
;; :: Reuses sql-connection-alist (modules/db.el) + ~/.authinfo.gpg for creds.
;; :: Read-only is enforced server-side via PGOPTIONS.

(require 'auth-source)
(require 'cl-lib)

;; :: NULL sentinel -- psql is told to print SQL NULL as this glyph (via -P null /
;; :: \pset null) so we can tell NULL apart from an empty string ''. The grid shows
;; :: it as "NULL"; the edit form (db-write.el) uses the token "NULL" for it too.
(defconst my/sql--null-sentinel "⌀"
  ":: marker psql emits for SQL NULL, distinguishing it from the empty string")

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
(defun my/sql--psql (conn-name sql &optional tuples-only extra-args)
  ":: run SQL against CONN-NAME via psql, read-only enforced server-side. Return
   (EXIT-CODE . OUTPUT); stderr (e.g. `connection refused') is merged into OUTPUT so
   callers can both show and gate on it. EXTRA-ARGS are spliced before `-c SQL'
   (e.g. (\"--csv\" \"-P\" \"null=⌀\") for a structured fetch)."
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
                        extra-args
                        (list "-c" sql))))
    (with-temp-buffer
      (let ((code (apply #'call-process "psql" nil t nil args)))
        (cons code (buffer-string))))))

;; ──────────────────────────────────────────────────────
;; :: Table list with cache (invalidate via refresh)
;; ──────────────────────────────────────────────────────
(defvar my/sql--table-cache (make-hash-table :test 'equal)
  ":: cached table names, keyed by connection name string")

(defun my/sql--tables (conn-name &optional refresh)
  ":: schema-qualified tables for CONN-NAME; cached unless REFRESH.
   A failed query (e.g. tunnel not up yet) is NOT cached and signals an error,
   so a later retry re-queries instead of serving poisoned error text."
  (let ((key (format "%s" conn-name)))
    (when refresh (remhash key my/sql--table-cache))
    (or (gethash key my/sql--table-cache)
        (let* ((res  (my/sql--psql conn-name
                       (concat "SELECT schemaname||'.'||tablename "
                               "FROM pg_catalog.pg_tables "
                               "WHERE schemaname NOT IN ('pg_catalog','information_schema') "
                               "ORDER BY 1;")
                       t))
               (code (car res))
               (out  (cdr res)))
          (if (zerop code)
              (puthash key (split-string out "\n" t "[ \t\r]+") my/sql--table-cache)
            ;; :: don't poison the cache with an error -- retry next time
            (user-error "psql failed: %s" (string-trim out)))))))

;; ──────────────────────────────────────────────────────
;; :: Result buffer: read-only, evil-navigable, refresh-in-place
;; ──────────────────────────────────────────────────────
(defvar-local my/sql--conn-name nil)
(defvar-local my/sql--table nil)
(defvar-local my/sql--where nil)
(defvar-local my/sql--limit 100)
(defvar-local my/sql--raw-sql nil
  ":: when set, render runs this SQL verbatim instead of the table-based query")
(defvar-local my/sql--title nil
  ":: optional explicit buffer title (e.g. a saved-query name)")
(defvar-local my/sql--order-by nil
  ":: column name to ORDER BY (nil = unsorted); set by my/sql-sort-column")
(defvar-local my/sql--order-desc nil
  ":: when my/sql--order-by is set, sort descending instead of ascending")
(defvar-local my/sql--select-cols nil
  ":: columns to display (nil = all, i.e. SELECT *); set by my/sql-select-columns.
   Identity (pk/ctid) columns are always fetched for edit/delete even if hidden.")

(define-derived-mode my/sql-result-mode special-mode "DB-Result"
  ":: read-only db result viewer"
  (setq-local truncate-lines t))

;; :: special-mode lands in evil `motion' state, where `,' is repeat-find-char,
;; :: not the localleader. Force normal state so `, f' etc. work as documented.
(when (fboundp 'evil-set-initial-state)
  (evil-set-initial-state 'my/sql-result-mode 'normal))

(defun my/sql--buffer-name ()
  ":: buffer title from current state -- explicit title (raw/saved query), else
   table + active filter. No earmuffs, so it shows up as a first-class buffer in
   `SPC ,' / the workspace switcher."
  (or my/sql--title
      (format "DB %s/%s%s"
              my/sql--conn-name my/sql--table
              (if (and my/sql--where (not (string-empty-p my/sql--where)))
                  (format " [%s]" my/sql--where) ""))))

;; ──────────────────────────────────────────────────────
;; :: Structured fetch -- CSV so values with commas/quotes/newlines round-trip
;; :: safely (psql --csv / \pset format csv). Routes through the open transaction
;; :: session when one is active (db-write.el) so SELECTs see uncommitted edits.
;; ──────────────────────────────────────────────────────
(defun my/sql--parse-csv (text)
  ":: parse RFC-4180 CSV TEXT into a list of rows, each a list of field strings.
   First row is the header. Handles quoted fields, embedded commas/newlines, and
   doubled-quote (\"\") escapes."
  (let ((i 0) (n (length text)) (rows '()) (row '()) (buf "")
        (quoted nil) (started nil))
    (while (< i n)
      (let ((c (aref text i)))
        (cond
         (quoted
          (cond
           ((eq c ?\")
            (if (and (< (1+ i) n) (eq (aref text (1+ i)) ?\"))
                (progn (setq buf (concat buf "\"")) (setq i (1+ i)))
              (setq quoted nil)))
           (t (setq buf (concat buf (char-to-string c))))))
         ((eq c ?\") (setq quoted t started t))
         ((eq c ?,)  (push buf row) (setq buf "" started t))
         ((eq c ?\n) (push buf row) (push (nreverse row) rows)
          (setq row '() buf "" started nil))
         ((eq c ?\r) nil)               ;; :: ignore CR (CRLF)
         (t (setq buf (concat buf (char-to-string c))) (setq started t))))
      (setq i (1+ i)))
    (when (or started row (> (length buf) 0))
      (push buf row) (push (nreverse row) rows))
    (nreverse rows)))

(defun my/sql--fetch-csv (conn sql)
  ":: run SQL and return its result as CSV text. Through the open txn session when
   active (read-your-own-writes), else a one-shot read-only psql call."
  (if (and (fboundp 'my/sql--txn-active-p) (my/sql--txn-active-p conn))
      (my/sql--txn-raw conn (concat sql "\n"))
    (cdr (my/sql--psql conn sql nil
                       (list "--csv"
                             "-P" (concat "null=" my/sql--null-sentinel)
                             "-P" "footer=off")))))

;; ──────────────────────────────────────────────────────
;; :: Primary-key discovery (per table, cached). Needed so every write targets a
;; :: unique row. No PK -> caller falls back to ctid.
;; ──────────────────────────────────────────────────────
(defvar my/sql--pk-cache (make-hash-table :test 'equal)
  ":: cached pk column lists, keyed by \"conn\\0table\"")

(defun my/sql--table-pk (conn table)
  ":: ordered list of TABLE's primary-key column names on CONN (cached). nil if none."
  (let* ((key (format "%s\0%s" conn table))
         (cached (gethash key my/sql--pk-cache 'miss)))
    (if (not (eq cached 'miss))
        cached
      (let* ((sql (format (concat "SELECT a.attname FROM pg_index i "
                                  "JOIN pg_attribute a ON a.attrelid = i.indrelid "
                                  "AND a.attnum = ANY(i.indkey) "
                                  "WHERE i.indrelid = '%s'::regclass AND i.indisprimary "
                                  "ORDER BY array_position(i.indkey, a.attnum);")
                          table))
             (res (my/sql--psql conn sql t))
             (cols (and (zerop (car res))
                        (split-string (cdr res) "\n" t "[ \t\r]+"))))
        (puthash key cols my/sql--pk-cache)
        cols))))

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

(defun my/sql--quote-ident (name)
  ":: SQL-quote an identifier (column name) for use in ORDER BY / column lists"
  (format "\"%s\"" (replace-regexp-in-string "\"" "\"\"" name)))

(defun my/sql--col-expr (col)
  ":: SELECT-list expression for COL -- the system `ctid' needs ::text + alias"
  (if (equal col "ctid") "ctid::text AS ctid" (my/sql--quote-ident col)))

(defun my/sql--order-clause ()
  ":: \" ORDER BY col DIR\" from buffer-local sort state, or \"\" when unsorted"
  (if my/sql--order-by
      (format " ORDER BY %s %s"
              (my/sql--quote-ident my/sql--order-by)
              (if my/sql--order-desc "DESC" "ASC"))
    ""))

(defun my/sql--build-select ()
  ":: plist (:pk PK-COLS :hide HIDE-COLS :sql SQL) for the current table buffer.
   Always fetches a row identifier (pk, or synthetic `ctid'); HIDE-COLS lists
   fetched-but-not-displayed columns (the identity cols the user didn't pick)."
  (let* ((pk    (my/sql--table-pk my/sql--conn-name my/sql--table))
         (ids   (or pk '("ctid")))
         (sel   my/sql--select-cols)
         (where (if (and my/sql--where (not (string-empty-p my/sql--where)))
                    (concat " WHERE " my/sql--where) ""))
         (order (my/sql--order-clause))
         (limit (if my/sql--limit (format " LIMIT %d" my/sql--limit) "")))
    (if (null sel)
        ;; :: no column selection -> SELECT * (+ ctid when pk-less)
        (if pk
            (list :pk pk :hide nil
                  :sql (format "SELECT * FROM %s%s%s%s;" my/sql--table where order limit))
          (list :pk '("ctid") :hide '("ctid")
                :sql (format "SELECT ctid::text AS ctid, * FROM %s%s%s%s;"
                             my/sql--table where order limit)))
      ;; :: explicit columns -> fetch selected + any identity cols not picked (hidden)
      (let* ((extra (cl-remove-if (lambda (c) (member c sel)) ids))
             (fetch (append sel extra)))
        (list :pk ids :hide extra
              :sql (format "SELECT %s FROM %s%s%s%s;"
                           (mapconcat #'my/sql--col-expr fetch ", ")
                           my/sql--table where order limit))))))

;; ──────────────────────────────────────────────────────
;; :: Grid render -- our own aligned table, with each row line carrying
;; :: `my/sql-pk' (row identity) and `my/sql-row' (all values) text properties so
;; :: edit/delete (db-write.el) read identity/values with zero text-parsing.
;; ──────────────────────────────────────────────────────
(defun my/sql--cell-display (raw)
  ":: how a raw field value is shown in the grid (NULL sentinel -> \"NULL\")"
  (if (and raw (string= raw my/sql--null-sentinel)) "NULL" (or raw "")))

(defun my/sql--pad (s width)
  ":: S truncated-with-ellipsis / space-padded to WIDTH display columns"
  (truncate-string-to-width s width nil ?\s "…"))

(defun my/sql--insert-grid (cols rows pk-cols &optional hide-cols)
  ":: render COLS/ROWS as an aligned grid; tag each data line with pk + row props.
   HIDE-COLS are fetched-for-identity-but-not-displayed columns (synthetic ctid,
   or pk/identity columns the user deselected via my/sql-select-columns)."
  (when cols
    (let* ((hide    hide-cols)
           (vis-idx (let ((acc '()) (i 0))
                      (dolist (c cols (nreverse acc))
                        (unless (member c hide) (push i acc))
                        (setq i (1+ i)))))
           (widths  (mapcar
                     (lambda (i)
                       (let ((w (string-width (nth i cols))))
                         (dolist (r rows)
                           (setq w (max w (string-width
                                           (my/sql--cell-display (nth i r))))))
                         (min w 40)))
                     vis-idx))
           (pairs   (cl-mapcar #'cons vis-idx widths)))
      ;; :: header + separator rule
      (insert (mapconcat (lambda (p) (my/sql--pad (nth (car p) cols) (cdr p))) pairs "  ")
              "\n")
      (insert (mapconcat (lambda (w) (make-string w ?─)) widths "  ") "\n")
      ;; :: data rows
      (dolist (r rows)
        (let ((start    (point))
              (pk       (when pk-cols
                          (mapcar (lambda (c)
                                    (cons c (nth (cl-position c cols :test #'equal) r)))
                                  pk-cols)))
              ;; :: editable values exclude hidden identity columns
              (rowalist (cl-loop for c in cols for v in r
                                 unless (member c hide) collect (cons c v))))
          ;; :: insert cell-by-cell so each cell carries `my/sql-col' -- lets RET
          ;; :: know which column the cursor is on (follow-foreign-key).
          (cl-loop for (idx . w) in pairs
                   for firstp = t then nil
                   do (unless firstp (insert "  "))
                      (let ((cstart (point)))
                        (insert (my/sql--pad (my/sql--cell-display (nth idx r)) w))
                        (put-text-property cstart (point) 'my/sql-col (nth idx cols))))
          (insert "\n")
          (add-text-properties start (point)
                               (list 'my/sql-pk pk 'my/sql-row rowalist)))))))

(defun my/sql--render ()
  ":: rebuild the query from buffer-local state and redraw the grid in place"
  (let* ((spec    (if my/sql--raw-sql
                      (list :pk nil :hide nil :sql my/sql--raw-sql)
                    (my/sql--build-select)))
         (pk-cols (plist-get spec :pk))
         (hide    (plist-get spec :hide))
         (sql     (plist-get spec :sql))
         (csv     (my/sql--fetch-csv my/sql--conn-name sql))
         (parsed  (my/sql--parse-csv csv))
         (cols    (car parsed))
         (rows    (cdr parsed))
         (txn-p   (and (fboundp 'my/sql--txn-active-p)
                       (my/sql--txn-active-p my/sql--conn-name)))
         (inhibit-read-only t))
    (rename-buffer (my/sql--buffer-name) t)  ;; :: keep title in sync with the query
    (erase-buffer)
    (when txn-p
      (insert (propertize
               (format "-- ⚠ TXN OPEN on %s —  , C commit   , K rollback\n" my/sql--conn-name)
               'face 'warning)))
    (insert (format "-- %s  @ %s\n-- %s\n\n"
                    (or my/sql--title my/sql--table) my/sql--conn-name sql))
    (my/sql--insert-grid cols rows pk-cols hide)
    (goto-char (point-min))))

;; ──────────────────────────────────────────────────────
;; :: Commands
;; ──────────────────────────────────────────────────────
(defun my/sql--open-table (conn table &optional where)
  ":: open (or refresh) a read-only browse buffer for CONN/TABLE, optionally
   filtered by WHERE. The buffer name embeds WHERE so a filtered view (e.g. a
   followed foreign key) never hijacks the plain table buffer."
  (let ((buf (get-buffer-create
              (format "DB %s/%s%s" conn table
                      (if (and where (not (string-empty-p where)))
                          (format " [%s]" where) "")))))
    (with-current-buffer buf
      (my/sql-result-mode)
      (setq my/sql--conn-name conn my/sql--table table
            my/sql--where where my/sql--limit 100
            my/sql--raw-sql nil my/sql--title nil
            my/sql--order-by nil my/sql--order-desc nil
            my/sql--select-cols nil)
      (my/sql--render))
    ;; :: register in the current Doom workspace so it shows in `SPC ,'
    (when (fboundp 'persp-add-buffer) (persp-add-buffer buf))
    (switch-to-buffer buf)))

(defun my/sql-browse (&optional refresh)
  ":: pick a db + table, open a read-only result buffer (C-u refreshes table cache)"
  (interactive "P")
  (my/sql--ensure-connections)
  (let* ((conn (completing-read "DB: "
                 (mapcar (lambda (c) (symbol-name (car c))) sql-connection-alist) nil t))
         (table (completing-read "Table: " (my/sql--tables conn refresh) nil t)))
    (my/sql--open-table conn table)))

(defun my/sql--open-raw (conn sql title &optional other-window)
  ":: open a read-only result buffer running raw SQL against CONN (used by saved
   queries and the scratch runner). Like `my/sql-browse' but freeform. With
   OTHER-WINDOW, pop it beside the current window instead of replacing it."
  (let ((buf (get-buffer-create title)))
    (with-current-buffer buf
      (my/sql-result-mode)
      (setq my/sql--conn-name conn my/sql--raw-sql sql my/sql--title title)
      (my/sql--render))
    (when (fboundp 'persp-add-buffer) (persp-add-buffer buf))
    (if other-window (pop-to-buffer buf) (switch-to-buffer buf))
    buf))

(defun my/sql-where ()
  ":: set/edit the WHERE clause (blank = unfiltered) and re-run"
  (interactive)
  (when my/sql--raw-sql
    (user-error "WHERE/LIMIT not available on a saved-query buffer"))
  (setq my/sql--where (read-string "WHERE: " my/sql--where))
  (my/sql--render))

(defun my/sql-limit (n)
  ":: set the row LIMIT (0 = no limit) and re-run"
  (interactive "nLIMIT (0 = no limit): ")
  (when my/sql--raw-sql
    (user-error "WHERE/LIMIT not available on a saved-query buffer"))
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
    (setq my/sql--table table my/sql--where nil
          my/sql--order-by nil my/sql--order-desc nil
          my/sql--select-cols nil)
    (my/sql--render)))  ;; :: render renames the buffer to match the new table

;; ──────────────────────────────────────────────────────
;; :: Follow a foreign key -- RET on an FK column opens the referenced table,
;; :: filtered to the referenced row. Needs the column under point (tagged as
;; :: `my/sql-col' in the grid) + FK metadata from the catalog (cached).
;; ──────────────────────────────────────────────────────
(defvar my/sql--fk-cache (make-hash-table :test 'equal)
  ":: cached FK maps, keyed by \"conn\\0table\"")

(defun my/sql--table-fks (conn table)
  ":: alist local-col -> plist(:schema :table :column) of FK targets (cached).
   Composite FKs yield one entry per component column."
  (let* ((key    (format "%s\0%s" conn table))
         (cached (gethash key my/sql--fk-cache 'miss)))
    (if (not (eq cached 'miss))
        cached
      (let* ((parts  (split-string table "\\."))
             (schema (if (cdr parts) (car parts) "public"))
             (name   (or (cadr parts) (car parts)))
             (sql    (format
                      (concat
                       "SELECT att.attname, ns.nspname, cl.relname, fatt.attname "
                       "FROM pg_constraint c "
                       "JOIN pg_class tbl ON tbl.oid = c.conrelid "
                       "JOIN pg_namespace tns ON tns.oid = tbl.relnamespace "
                       "JOIN unnest(c.conkey)  WITH ORDINALITY AS lk(attnum, ord) ON true "
                       "JOIN unnest(c.confkey) WITH ORDINALITY AS fk(attnum, ord) ON fk.ord = lk.ord "
                       "JOIN pg_attribute att  ON att.attrelid = c.conrelid AND att.attnum = lk.attnum "
                       "JOIN pg_class cl       ON cl.oid = c.confrelid "
                       "JOIN pg_namespace ns   ON ns.oid = cl.relnamespace "
                       "JOIN pg_attribute fatt ON fatt.attrelid = c.confrelid AND fatt.attnum = fk.attnum "
                       "WHERE c.contype = 'f' AND tbl.relname = '%s' AND tns.nspname = '%s';")
                      name schema))
             (res    (my/sql--psql conn sql t))
             (alist  (when (zerop (car res))
                       (mapcar (lambda (line)
                                 (let ((f (split-string line "|")))
                                   (cons (nth 0 f)
                                         (list :schema (nth 1 f)
                                               :table  (nth 2 f)
                                               :column (nth 3 f)))))
                               (split-string (cdr res) "\n" t)))))
        (puthash key alist my/sql--fk-cache)
        alist))))

(defvar my/sql--nav-stack nil
  ":: stack of result buffers to return to via `my/sql-back' (C-o), pushed on FK follow")

(defun my/sql-follow-fk ()
  ":: if point is on a foreign-key column, open the referenced table filtered to
   the referenced row (bound to RET in a result buffer)"
  (interactive)
  (unless (and (derived-mode-p 'my/sql-result-mode) my/sql--table (not my/sql--raw-sql))
    (user-error "Foreign keys can only be followed in a table browse buffer"))
  (let ((col (get-text-property (point) 'my/sql-col))
        (row (get-text-property (point) 'my/sql-row)))
    (unless col (user-error "No column under point"))
    (let ((fk (cdr (assoc col (my/sql--table-fks my/sql--conn-name my/sql--table)))))
      (unless fk (user-error "%s is not a foreign key column" col))
      (let ((val (cdr (assoc col row))))
        (when (or (null val) (string= val my/sql--null-sentinel))
          (user-error "%s is NULL -- nothing to follow" col))
        ;; :: remember where we came from so C-o can return (after all guards pass)
        (push (current-buffer) my/sql--nav-stack)
        (my/sql--open-table
         my/sql--conn-name
         (format "%s.%s" (plist-get fk :schema) (plist-get fk :table))
         (format "%s = '%s'" (plist-get fk :column)
                 (replace-regexp-in-string "'" "''" val)))))))

(defun my/sql-back ()
  ":: return to the buffer we followed a foreign key from, vim `C-o' style"
  (interactive)
  (let ((buf (pop my/sql--nav-stack)))
    (while (and buf (not (buffer-live-p buf)))   ;; :: skip buffers since killed
      (setq buf (pop my/sql--nav-stack)))
    (if buf
        (switch-to-buffer buf)
      (user-error "No table to go back to"))))

;; ──────────────────────────────────────────────────────
;; :: JSON view + CSV export -- both operate on the CURRENT view (its WHERE/LIMIT)
;; :: and route through my/sql--fetch-csv, so they reflect exactly what's on screen
;; :: (txn-aware: uncommitted edits included).
;; ──────────────────────────────────────────────────────
(defun my/sql--goto-column (col)
  ":: move point to the first data cell of column COL (used after a re-render so a
   repeated sort lands back on the same column)"
  (goto-char (point-min))
  (let (found)
    (while (and (not found) (not (eobp)))
      (if (equal (get-text-property (point) 'my/sql-col) col)
          (setq found t)
        (goto-char (or (next-single-property-change (point) 'my/sql-col) (point-max)))))
    found))

(defun my/sql-sort-column (&optional clear)
  ":: sort the current table by the column under point (ASC; toggle to DESC by
   repeating on the same column). With prefix arg CLEAR, drop the sort."
  (interactive "P")
  (unless (and (derived-mode-p 'my/sql-result-mode) my/sql--table (not my/sql--raw-sql))
    (user-error "Sorting only works in a table browse buffer"))
  (if clear
      (progn (setq my/sql--order-by nil my/sql--order-desc nil)
             (my/sql--render)
             (message "Sort cleared"))
    (let ((col (get-text-property (point) 'my/sql-col)))
      (unless col (user-error "Move point onto a column to sort by it"))
      (if (equal col my/sql--order-by)
          (setq my/sql--order-desc (not my/sql--order-desc))   ;; :: toggle direction
        (setq my/sql--order-by col my/sql--order-desc nil))    ;; :: new column, ASC
      (my/sql--render)
      (my/sql--goto-column col)
      (message "Sorted by %s %s" col (if my/sql--order-desc "DESC" "ASC")))))

(defun my/sql--data-table-name ()
  ":: bare, filename-safe table name for default export/view buffer names"
  (let ((n (car (last (split-string (or my/sql--table my/sql--title "query") "\\.")))))
    (replace-regexp-in-string "[^A-Za-z0-9_-]" "_" n)))

(defun my/sql--current-data-sql ()
  ":: SQL for the current view's data -- user-facing columns only (no synthetic
   ctid identifier that my/sql--build-select adds for pk-less tables)"
  (if my/sql--raw-sql
      my/sql--raw-sql
    (let ((cols  (if my/sql--select-cols
                     (mapconcat #'my/sql--quote-ident my/sql--select-cols ", ")
                   "*"))
          (where (if (and my/sql--where (not (string-empty-p my/sql--where)))
                     (concat " WHERE " my/sql--where) ""))
          (order (my/sql--order-clause))
          (limit (if my/sql--limit (format " LIMIT %d" my/sql--limit) "")))
      (format "SELECT %s FROM %s%s%s%s;" cols my/sql--table where order limit))))

(defun my/sql-json-view ()
  ":: show the current view as pretty-printed JSON in a side buffer (read-only)"
  (interactive)
  (unless (derived-mode-p 'my/sql-result-mode) (user-error "Not a result buffer"))
  (require 'json)
  (let* ((inner (replace-regexp-in-string ";[ \t\n]*\\'" "" (my/sql--current-data-sql)))
         ;; :: let Postgres build the JSON so types/nulls/nested json are correct
         (sql   (format "SELECT json_agg(t) FROM (%s) t;" inner))
         (cell  (car (cadr (my/sql--parse-csv
                            (my/sql--fetch-csv my/sql--conn-name sql)))))
         (json  (if (or (null cell)
                        (string= cell "")
                        (string= cell my/sql--null-sentinel))
                    "[]" cell))
         (buf   (get-buffer-create (format "*DB JSON: %s*" (my/sql--data-table-name)))))
    (with-current-buffer buf
      (cond ((fboundp 'json-mode) (json-mode))
            ((fboundp 'js-json-mode) (js-json-mode))
            (t (js-mode)))
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert json)
        (ignore-errors (json-pretty-print-buffer))
        (goto-char (point-min)))
      (view-mode 1))                        ;; :: read-only + `q' to bury
    (when (fboundp 'persp-add-buffer) (persp-add-buffer buf))
    (display-buffer buf)))

(defun my/sql-export-csv (file)
  ":: write the current view to FILE as CSV (header + rows). Prompts for a path."
  (interactive
   (progn
     (unless (derived-mode-p 'my/sql-result-mode) (user-error "Not a result buffer"))
     (list (read-file-name "Export CSV to: " nil nil nil
                           (concat (my/sql--data-table-name) ".csv")))))
  (let* ((csv   (my/sql--fetch-csv my/sql--conn-name (my/sql--current-data-sql)))
         ;; :: psql prints the null sentinel; emit standard CSV (empty for NULL)
         (clean (replace-regexp-in-string (regexp-quote my/sql--null-sentinel) "" csv))
         (rows  (length (cdr (my/sql--parse-csv clean)))))
    (when (and (file-exists-p file)
               (not (yes-or-no-p (format "%s exists -- overwrite? " file))))
      (user-error "Cancelled"))
    (with-temp-file file (insert clean))
    (message "Exported %d row(s) to %s" rows (abbreviate-file-name file))))

;; ──────────────────────────────────────────────────────
;; :: Column selector -- a checklist buffer to pick which columns to display.
;; :: Starts with the current set checked; apply re-runs with only those columns
;; :: (identity columns are still fetched behind the scenes for edit/delete).
;; ──────────────────────────────────────────────────────
(defvar-local my/sql--colsel-source nil)
(defvar-local my/sql--colsel-cols nil)
(defvar-local my/sql--colsel-checked nil)

(define-derived-mode my/sql-colsel-mode special-mode "DB-Columns"
  ":: checklist to choose which table columns to display")

(when (fboundp 'evil-set-initial-state)        ;; :: normal state so :n keys work
  (evil-set-initial-state 'my/sql-colsel-mode 'normal))

(defun my/sql--colsel-render ()
  ":: redraw the checklist, keeping point on its line"
  (let ((inhibit-read-only t) (ln (line-number-at-pos)))
    (erase-buffer)
    (insert (propertize
             "# columns to show   TAB/RET toggle   a all   n none   C-c C-c apply   q cancel\n\n"
             'face 'font-lock-comment-face))
    (dolist (c my/sql--colsel-cols)
      (insert (propertize
               (format "[%s] %s\n" (if (member c my/sql--colsel-checked) "x" " ") c)
               'my/sql-colsel-col c)))
    (goto-char (point-min))
    (forward-line (1- ln))))

(defun my/sql-colsel-toggle ()
  ":: toggle the column on the current line"
  (interactive)
  (let ((c (get-text-property (point) 'my/sql-colsel-col)))
    (when c
      (setq my/sql--colsel-checked
            (if (member c my/sql--colsel-checked)
                (remove c my/sql--colsel-checked)   ;; :: non-destructive (no shared-list mutation)
              (cons c my/sql--colsel-checked)))
      (my/sql--colsel-render))))

(defun my/sql-colsel-all ()
  ":: check every column"
  (interactive)
  (setq my/sql--colsel-checked (copy-sequence my/sql--colsel-cols))
  (my/sql--colsel-render))

(defun my/sql-colsel-none ()
  ":: uncheck every column"
  (interactive)
  (setq my/sql--colsel-checked nil)
  (my/sql--colsel-render))

(defun my/sql-colsel-apply ()
  ":: apply the checked columns to the source table buffer and re-run"
  (interactive)
  (let* ((src     my/sql--colsel-source)
         ;; :: keep natural column order; all-checked means SELECT * (nil)
         (checked (cl-remove-if-not (lambda (c) (member c my/sql--colsel-checked))
                                    my/sql--colsel-cols))
         (all     my/sql--colsel-cols))
    (unless checked (user-error "Select at least one column"))
    (when (buffer-live-p src)
      (with-current-buffer src
        (setq my/sql--select-cols (unless (equal checked all) checked))
        (my/sql--render)))
    (quit-window t)
    (message "Showing %s"
             (if (equal checked all) "all columns"
               (format "%d of %d columns" (length checked) (length all))))))

(defun my/sql-select-columns ()
  ":: open a checklist to choose which columns the current table shows"
  (interactive)
  (unless (and (derived-mode-p 'my/sql-result-mode) my/sql--table (not my/sql--raw-sql))
    (user-error "Column selection only works in a table browse buffer"))
  (let* ((cols    (my/sql--table-columns my/sql--conn-name my/sql--table))
         (current (or my/sql--select-cols cols))   ;; :: nil means all shown
         (src     (current-buffer))
         (buf     (get-buffer-create (format "*DB columns: %s*" (my/sql--data-table-name)))))
    (unless cols (user-error "Could not read columns for %s" my/sql--table))
    (with-current-buffer buf
      (my/sql-colsel-mode)
      (setq my/sql--colsel-source  src
            my/sql--colsel-cols    cols
            ;; :: own copy -- cl-remove-if-not can alias `cols' when nothing is removed
            my/sql--colsel-checked (copy-sequence
                                    (cl-remove-if-not (lambda (c) (member c current)) cols)))
      (my/sql--colsel-render))
    (when (fboundp 'persp-add-buffer) (persp-add-buffer buf))
    (pop-to-buffer buf)))

(map! :map my/sql-colsel-mode-map
      :n "TAB"     #'my/sql-colsel-toggle
      :n [tab]     #'my/sql-colsel-toggle
      :n "RET"     #'my/sql-colsel-toggle
      :n [return]  #'my/sql-colsel-toggle
      :n "a"       #'my/sql-colsel-all
      :n "n"       #'my/sql-colsel-none
      :n "q"       #'quit-window
      "C-c C-c"    #'my/sql-colsel-apply
      "C-c C-k"    #'quit-window)

;; ──────────────────────────────────────────────────────
;; :: In-buffer keys via localleader -- leaves hjkl/search motions untouched
;; ──────────────────────────────────────────────────────
(map! :map my/sql-result-mode-map
      :n "q"  #'quit-window
      ;; :: RET follows an FK to the referenced row; C-o jumps back (vim-style)
      :n "RET"      #'my/sql-follow-fk
      :n [return]   #'my/sql-follow-fk
      :n "C-o"      #'my/sql-back
      ;; :: write ops (db-write.el) -- vim-style row delete
      :n "dd" #'my/sql-delete-row
      :v "d"  #'my/sql-delete-rows
      :localleader
      :desc "Filter (WHERE)" "f" #'my/sql-where
      :desc "Set row LIMIT"  "l" #'my/sql-limit
      :desc "Re-run query"   "r" #'my/sql-refresh
      :desc "Refresh tables" "R" #'my/sql-refresh-tables
      :desc "Switch table"   "t" #'my/sql-switch-table
      :desc "Save query"     "s" #'my/sql-save-query
      ;; :: sort by the column under point (repeat = toggle dir, C-u = clear)
      :desc "Sort column"    "S" #'my/sql-sort-column
      ;; :: choose which columns to display (checklist)
      :desc "Select columns" "c" #'my/sql-select-columns
      ;; :: view / export the current result set
      :desc "JSON view"      "j" #'my/sql-json-view
      :desc "Export CSV"     "E" #'my/sql-export-csv
      ;; :: write mode -- edit a row + transaction control (db-write.el).
      ;; :: commit/rollback are capitalised (C/K) to flag them as weighty actions.
      :desc "Edit row"       "e" #'my/sql-edit-row
      :desc "Insert row"     "i" #'my/sql-insert-row
      :desc "Commit txn"     "C" #'my/sql-txn-commit-here
      :desc "Rollback txn"   "K" #'my/sql-txn-rollback-here
      :desc "Begin txn"      "x" #'my/sql-txn-begin-here)
