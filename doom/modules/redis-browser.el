;;; modules/redis-browser.el -*- lexical-binding: t; -*-

;; :: The buffer UI for Redis: a SCAN'd key grid, a type-aware value inspector,
;; :: an edit form, a JSON view, an INFO dashboard and a replies pad. Mirrors
;; :: db-browser.el + the edit form from db-write.el; loads AFTER redis.el.
;; ::
;; :: In a keys view (SPC d R b):
;; ::   RET inspect   C-o back   y yank key   dd delete (visual d = many)   q bury
;; ::   , f filter (SCAN pattern)   , l limit      , r refresh   , S sort column
;; ::   , j JSON      , e edit      , i insert key  , s save
;; ::   , T type filter   , d switch db   , k inspect a named key   , I INFO
;; ::
;; :: In an inspector:
;; ::   RET JSON-view the value   C-o back   y yank value   dd delete element
;; ::   , e edit   , i insert element   , r refresh   , j JSON   , l limit   , s save
;; ::   , t TTL    , n rename          , D delete key      , I INFO
;; ::
;; :: Writes always confirm. There is no FLUSHDB/FLUSHALL here on purpose.

(require 'cl-lib)
(require 'json)
(require 'subr-x)

;; ──────────────────────────────────────────────────────
;; :: Buffer state
;; ::
;; :: `my/redis--conn' / `my/redis--db' are declared in redis.el so the scratch
;; :: pad and these buffers share them.
;; ──────────────────────────────────────────────────────

(defvar-local my/redis--view nil
  ":: Which view this buffer renders: `keys', `key', `replies' or `info'.")
(defvar-local my/redis--title nil)
(defvar-local my/redis--pattern "*"   ":: SCAN MATCH pattern for a keys view.")
(defvar-local my/redis--type nil      ":: SCAN TYPE filter, or nil for all types.")
(defvar-local my/redis--limit nil     ":: Max keys / elements fetched.")
(defvar-local my/redis--sort-col nil)
(defvar-local my/redis--sort-desc nil)
(defvar-local my/redis--partial nil   ":: Non-nil when the fetch was cut short.")
(defvar-local my/redis--cols nil      ":: Column names of the rendered grid.")
(defvar-local my/redis--rows nil
  ":: Parsed rows as alists (COLUMN . RAW-REPLY-VALUE). Kept so sort / JSON /
   save can work without re-fetching.")
(defvar-local my/redis--key nil       ":: Key being inspected.")
(defvar-local my/redis--key-type nil)
(defvar-local my/redis--key-total nil ":: Full element count, vs what's shown.")
(defvar-local my/redis--key-meta nil  ":: Alist of header facts (ttl, encoding...).")
(defvar-local my/redis--replies nil   ":: List of (COMMAND-LINE . REPLY).")
(defvar-local my/redis--lines nil     ":: Command lines behind a replies view.")
(defvar-local my/redis--info-section nil)

(defvar my/redis--nav-stack nil
  ":: Buffers to return to with C-o, pushed when drilling into a key.")

;; ──────────────────────────────────────────────────────
;; :: Mode
;; ──────────────────────────────────────────────────────

(define-derived-mode my/redis-result-mode special-mode "Redis"
  ":: Read-only Redis viewer. One mode for all four views (see `my/redis--view')
   so the single concrete major-mode name can be listed in config.el's
   word-wrap / zoom exclusion lists, which match `major-mode' exactly."
  (setq-local truncate-lines t)
  (buffer-disable-undo))

;; :: special-mode lands in evil `motion' state, where `,' is repeat-find-char
;; :: rather than the localleader -- same fix as my/sql-result-mode.
(when (fboundp 'evil-set-initial-state)
  (evil-set-initial-state 'my/redis-result-mode 'normal))

;; :: Dock at the bottom, full width, like the DB result buffer. No `:slot', so
;; :: Redis and DB results deliberately SHARE the bottom slot and replace each
;; :: other rather than splitting it in half.
(when (fboundp 'set-popup-rule!)
  (set-popup-rule! '(derived-mode . my/redis-result-mode)
    :side 'bottom :size 0.4 :select t :modeline t :quit nil :ttl nil))

;; :: `switch-to-buffer' ignores display-buffer-alist entirely, so anything that
;; :: reaches one of these buffers that way (SPC b b, persp restoring a
;; :: workspace) would drop it wherever point happens to be. Reroute to
;; :: `pop-to-buffer' so they always land back in their popup slot.
(defadvice! my/redis-result-buffer-obeys-popup-rule-a (fn buffer-or-name &rest args)
  :around #'switch-to-buffer
  (let ((buf (get-buffer buffer-or-name)))
    (if (and buf (with-current-buffer buf (derived-mode-p 'my/redis-result-mode)))
        (pop-to-buffer buf)
      (apply fn buffer-or-name args))))

(defun my/redis--sanitise-name (s &optional max)
  ":: Make S safe and short enough to be a buffer name. Keys can contain control
   characters and be arbitrarily long; a hash keeps distinct long keys distinct."
  (let* ((clean (replace-regexp-in-string "[[:cntrl:]]" "." (or s "")))
         (max   (or max 60)))
    (if (<= (length clean) max)
        clean
      (concat (substring clean 0 (- max 9))
              "…" (substring (secure-hash 'md5 s) 0 8)))))

(defun my/redis--buffer (name)
  ":: Create/reuse a result buffer, put it in the workspace, and show it."
  (let ((buf (get-buffer-create name)))
    (when (fboundp 'persp-add-buffer) (persp-add-buffer buf))
    buf))

(defun my/redis--show (buf)
  (pop-to-buffer buf)
  buf)

(defun my/redis--assert-view (&rest views)
  (unless (and (derived-mode-p 'my/redis-result-mode)
               (memq my/redis--view views))
    (user-error "Not available in this buffer")))

;; ──────────────────────────────────────────────────────
;; :: Grid -- same algorithm as my/sql--insert-grid
;; ──────────────────────────────────────────────────────

(defun my/redis--pad (s width)
  (truncate-string-to-width s width nil ?\s "…"))

(defun my/redis--insert-grid (cols rows row-props)
  ":: Render COLS/ROWS as an aligned grid. ROWS are alists (COL . RAW); each
   line gets the corresponding plist from ROW-PROPS as text properties, and each
   cell carries `my/redis-col' so sorting knows the column under point."
  (when cols
    (let* ((disp   (mapcar (lambda (r)
                             (mapcar (lambda (c)
                                       (my/redis--cell-display (cdr (assoc c r))))
                                     cols))
                           rows))
           (widths (let ((i -1))
                     (mapcar (lambda (c)
                               (setq i (1+ i))
                               (let ((w (string-width c)))
                                 (dolist (d disp)
                                   (setq w (max w (string-width (nth i d)))))
                                 (min w my/redis-max-col-width)))
                             cols))))
      (insert (string-join (cl-mapcar #'my/redis--pad cols widths) "  ") "\n")
      (insert (string-join (mapcar (lambda (w) (make-string w ?─)) widths) "  ") "\n")
      (cl-loop for d in disp
               for props in row-props
               do (let ((start (point)))
                    (cl-loop for c in cols
                             for v in d
                             for w in widths
                             for firstp = t then nil
                             do (unless firstp (insert "  "))
                                (let ((cs (point)))
                                  (insert (my/redis--pad v w))
                                  (put-text-property cs (point) 'my/redis-col c)))
                    (insert "\n")
                    (when props (add-text-properties start (point) props)))))))

(defun my/redis--sort-key (v &optional col)
  ":: Comparable form of a raw cell value; nil means `sorts last'.
   TTL is special-cased: -1 (no expiry) and -2 (gone) are sentinels, not
   durations, so sorting by ttl must not park them ahead of a real 30s."
  (cond ((my/redis--error-p v) nil)
        ((eq v :null) nil)
        ((and (equal col "ttl") (memql (my/redis--int v) '(-1 -2))) nil)
        ((numberp v) v)
        ((stringp v) v)
        (t nil)))

(defun my/redis--sort-rows (rows col desc)
  ":: Stably sort ROWS by COL. Numeric when every present value is a number;
   missing / failed values sort last in BOTH directions."
  (if (null col)
      rows
    (let* ((val     (lambda (r) (my/redis--sort-key (cdr (assoc col r)) col)))
           (present (cl-remove-if-not (lambda (r) (funcall val r)) rows))
           (absent  (cl-remove-if     (lambda (r) (funcall val r)) rows))
           (numeric (and present
                         (cl-every (lambda (r) (numberp (funcall val r))) present)))
           (less    (if numeric
                        (lambda (a b) (< (funcall val a) (funcall val b)))
                      (lambda (a b) (string-lessp (format "%s" (funcall val a))
                                                  (format "%s" (funcall val b))))))
           (cmp     (if desc (lambda (a b) (funcall less b a)) less)))
      (append (sort (copy-sequence present) cmp) absent))))

(defun my/redis--goto-column (col)
  ":: Put point on the first data cell of COL (so a repeated sort stays put)."
  (goto-char (point-min))
  (let (found)
    (while (and (not found) (not (eobp)))
      (if (equal (get-text-property (point) 'my/redis-col) col)
          (setq found t)
        (goto-char (or (next-single-property-change (point) 'my/redis-col)
                       (point-max)))))
    found))

(defun my/redis--header (fmt &rest args)
  (insert (propertize (concat "# " (apply #'format fmt args) "\n")
                      'face 'font-lock-comment-face)))

;; ──────────────────────────────────────────────────────
;; :: Keys view
;; ──────────────────────────────────────────────────────

(defun my/redis--scan (conn db pattern type limit)
  ":: Our own SCAN loop (redis-cli's --scan has no TYPE filter).
   Returns (KEYS . PARTIAL-P); PARTIAL-P when we stopped early."
  (let ((cursor "0") (keys '()) (calls 0) (partial nil) (seen (make-hash-table :test 'equal)))
    (catch 'done
      (while t
        (let* ((args (append (list "SCAN" cursor "MATCH" pattern
                                   "COUNT" (number-to-string my/redis-scan-count))
                             (when type (list "TYPE" type))))
               (rep  (car (my/redis--batch conn db (list args)))))
          (when (my/redis--error-p rep)
            (if (and type (string-match-p "syntax error" (format "%s" (cdr rep))))
                (user-error "SCAN ... TYPE needs Redis >= 6")
              (user-error "SCAN failed: %s" (cdr rep))))
          (setq cursor (car rep))
          (dolist (k (cadr rep))
            (unless (gethash k seen)
              (puthash k t seen)
              (push k keys)))
          (setq calls (1+ calls))
          (when (>= (length keys) limit)
            (setq partial (not (equal cursor "0"))) (throw 'done t))
          (when (equal cursor "0") (throw 'done t))
          (when (>= calls my/redis-scan-max-calls)
            (setq partial t) (throw 'done t)))))
    (cons (nreverse (if (> (length keys) limit)
                        (nthcdr (- (length keys) limit) keys)
                      keys))
          partial)))

(defconst my/redis--size-command
  '(("string" . "STRLEN") ("hash" . "HLEN") ("list" . "LLEN")
    ("set" . "SCARD") ("zset" . "ZCARD") ("stream" . "XLEN"))
  ":: Command giving the natural `size' of each key type.")

(defun my/redis--keys-rows (conn db keys)
  ":: Build the keys-grid rows: two batches, TYPE+TTL then a size per type."
  (let* ((meta  (my/redis--batch
                 conn db
                 (cl-loop for k in keys append (list (list "TYPE" k) (list "TTL" k)))))
         (types (cl-loop for i from 0 below (length keys)
                         collect (nth (* 2 i) meta)))
         (ttls  (cl-loop for i from 0 below (length keys)
                         collect (nth (1+ (* 2 i)) meta)))
         (sizable (cl-loop for k in keys for ty in types
                           when (assoc (format "%s" ty) my/redis--size-command)
                           collect (cons k ty)))
         (sizes (when sizable
                  (my/redis--batch
                   conn db
                   (mapcar (lambda (kt)
                             (list (cdr (assoc (format "%s" (cdr kt))
                                               my/redis--size-command))
                                   (car kt)))
                           sizable))))
         (size-of (let ((h (make-hash-table :test 'equal)))
                    (cl-loop for kt in sizable for s in sizes
                             do (puthash (car kt) s h))
                    h)))
    (cl-loop for k in keys for ty in types for ttl in ttls
             collect (list (cons "key" k)
                           (cons "type" ty)
                           (cons "ttl" ttl)
                           (cons "size" (gethash k size-of "-"))))))

(defun my/redis--render-keys ()
  ":: (Re)fetch and draw the keys grid from this buffer's state."
  (let* ((conn my/redis--conn)
         (db   my/redis--db)
         (limit (or my/redis--limit my/redis-default-limit))
         (dbsize (my/redis--call conn db "DBSIZE"))
         (scan  (my/redis--scan conn db my/redis--pattern my/redis--type limit))
         (keys  (car scan))
         (rows  (if keys (my/redis--keys-rows conn db keys) '()))
         (inhibit-read-only t))
    (setq my/redis--partial (cdr scan)
          my/redis--cols '("key" "type" "ttl" "size")
          my/redis--rows (my/redis--sort-rows rows my/redis--sort-col
                                              my/redis--sort-desc))
    (erase-buffer)
    (my/redis--header "%s  %s:%s  db %s   pattern %s%s"
                      (plist-get conn :name) (plist-get conn :host)
                      (plist-get conn :port) db my/redis--pattern
                      (if my/redis--type (format "   type %s" my/redis--type) ""))
    (my/redis--header "DBSIZE %s   showing %d (limit %d)%s"
                      (my/redis--cell-display dbsize) (length my/redis--rows) limit
                      (if my/redis--sort-col
                          (format "   sorted by %s %s" my/redis--sort-col
                                  (if my/redis--sort-desc "desc" "asc")) ""))
    (when my/redis--partial
      (insert (propertize "# partial scan -- narrow the pattern or raise the limit\n"
                          'face 'warning)))
    (insert "\n")
    (if (null my/redis--rows)
        (insert "(no keys match)\n")
      ;; :: display TTL as a duration but keep the raw seconds in `my/redis--rows'
      ;; :: so sorting stays numeric.
      (let ((shown (mapcar (lambda (r)
                             (mapcar (lambda (kv)
                                       (if (equal (car kv) "ttl")
                                           (cons "ttl" (my/redis--humanise-ttl (cdr kv)))
                                         kv))
                                     r))
                           my/redis--rows)))
        (my/redis--insert-grid
         my/redis--cols shown
         (mapcar (lambda (r)
                   (let ((k (cdr (assoc "key" r))))
                     (list 'my/redis-key k
                           'my/redis-row r
                           'my/redis-binary (and (consp k) t))))
                 my/redis--rows))))
    (goto-char (point-min))))

(defun my/redis--keys-buffer-name (conn db pattern)
  (my/redis--sanitise-name
   (format "Redis %s db%s%s" (plist-get conn :name) db
           (if (equal pattern "*") "" (format " [%s]" pattern)))
   70))

(defun my/redis--open-keys (conn db &optional pattern type limit sort-col sort-desc)
  ":: Open (or refresh) a keys view."
  (let ((buf (my/redis--buffer (my/redis--keys-buffer-name conn db (or pattern "*")))))
    (with-current-buffer buf
      (my/redis-result-mode)
      (setq my/redis--conn conn my/redis--db db
            my/redis--view 'keys
            my/redis--pattern (or pattern "*")
            my/redis--type type
            my/redis--limit (or limit my/redis-default-limit)
            my/redis--sort-col sort-col
            my/redis--sort-desc sort-desc
            my/redis--key nil my/redis--title nil)
      (my/redis--render-keys))
    (my/redis--show buf)))

(defun my/redis-browse (&optional arg)
  ":: Pick a connection and browse its keys (SPC d R b). C-u prompts for a db."
  (interactive "P")
  (let* ((conn (my/redis--read-conn "Browse redis: "))
         (db   (if arg (read-number "Logical db: " (plist-get conn :db))
                 (plist-get conn :db))))
    (my/redis--open-keys conn db "*")))

;; ──────────────────────────────────────────────────────
;; :: Inspector
;; ──────────────────────────────────────────────────────

(defun my/redis--stream-fields (fields)
  ":: Stream entry field list -> \"f=v  f2=v2\"."
  (string-join (mapcar (lambda (kv) (format "%s=%s"
                                            (my/redis--cell-display (car kv))
                                            (my/redis--cell-display (cdr kv))))
                       (my/redis--pairs fields))
               "  "))

(cl-defun my/redis--render-key ()
  ":: (Re)fetch and draw the inspector for `my/redis--key'."
  (let* ((conn my/redis--conn)
         (db   my/redis--db)
         (key  my/redis--key)
         (limit (or my/redis--limit my/redis-default-limit))
         (meta (my/redis--batch conn db (list (list "TYPE" key)
                                              (list "TTL" key)
                                              (list "OBJECT" "ENCODING" key))))
         (type (format "%s" (nth 0 meta)))
         (ttl  (nth 1 meta))
         (enc  (nth 2 meta))
         (inhibit-read-only t)
         cols rows props total note)
    (when (equal type "none")
      (erase-buffer)
      (my/redis--header "%s  key %s" (plist-get conn :name) key)
      (insert "\n(key does not exist -- it may have expired)\n")
      (setq my/redis--key-type nil my/redis--rows nil my/redis--cols nil)
      (goto-char (point-min))
      (cl-return-from my/redis--render-key nil))
    (setq my/redis--key-type type)
    (pcase type
      ("string"
       (let* ((len (my/redis--int (car (my/redis--batch conn db
                                                        (list (list "STRLEN" key))))
                                  0))
              (val (if (> len my/redis-value-max-chars)
                       (progn (setq note (format "truncated to %d of %d bytes"
                                                 my/redis-value-max-chars len))
                              (car (my/redis--batch
                                    conn db
                                    (list (list "GETRANGE" key "0"
                                                (number-to-string
                                                 (1- my/redis-value-max-chars)))))))
                     (car (my/redis--batch conn db (list (list "GET" key)))))))
         (setq total len cols nil rows (list val))))
      ("hash"
       (let ((n (my/redis--int (car (my/redis--batch conn db (list (list "HLEN" key)))) 0)))
         (setq total n cols '("field" "value"))
         (let ((pairs (if (<= n limit)
                          (my/redis--pairs (car (my/redis--batch
                                                 conn db (list (list "HGETALL" key)))))
                        (setq note (format "showing first %d of %d" limit n))
                        (my/redis--pairs
                         (cadr (car (my/redis--batch
                                     conn db
                                     (list (list "HSCAN" key "0" "COUNT"
                                                 (number-to-string limit))))))))))
           (setq rows (mapcar (lambda (kv) (list (cons "field" (car kv))
                                                 (cons "value" (cdr kv))))
                              pairs)
                 props (mapcar (lambda (kv)
                                 (list 'my/redis-elem (list :kind 'hash :field (car kv))
                                       'my/redis-value (cdr kv)))
                               pairs)))))
      ("list"
       (let* ((n (my/redis--int (car (my/redis--batch conn db (list (list "LLEN" key)))) 0))
              (vals (car (my/redis--batch conn db
                                          (list (list "LRANGE" key "0"
                                                      (number-to-string (1- limit))))))))
         (when (> n limit) (setq note (format "showing first %d of %d" limit n)))
         (setq total n cols '("index" "value")
               rows (cl-loop for v in vals for i from 0
                             collect (list (cons "index" i) (cons "value" v)))
               props (cl-loop for v in vals for i from 0
                              collect (list 'my/redis-elem
                                            (list :kind 'list :index i :value v)
                                            'my/redis-value v)))))
      ("set"
       (let* ((n (my/redis--int (car (my/redis--batch conn db (list (list "SCARD" key)))) 0))
              (vals (if (<= n limit)
                        (car (my/redis--batch conn db (list (list "SMEMBERS" key))))
                      (setq note (format "showing first %d of %d" limit n))
                      (cadr (car (my/redis--batch
                                  conn db
                                  (list (list "SSCAN" key "0" "COUNT"
                                              (number-to-string limit)))))))))
         (setq total n cols '("member")
               rows (mapcar (lambda (v) (list (cons "member" v))) vals)
               props (mapcar (lambda (v) (list 'my/redis-elem
                                               (list :kind 'set :member v)
                                               'my/redis-value v))
                             vals))))
      ("zset"
       (let* ((n (my/redis--int (car (my/redis--batch conn db (list (list "ZCARD" key)))) 0))
              (pairs (my/redis--pairs
                      (car (my/redis--batch
                            conn db
                            (list (list "ZRANGE" key "0"
                                        (number-to-string (1- limit)) "WITHSCORES")))))))
         (when (> n limit) (setq note (format "showing first %d of %d" limit n)))
         (setq total n cols '("member" "score")
               rows (mapcar (lambda (kv) (list (cons "member" (car kv))
                                               (cons "score" (cdr kv))))
                            pairs)
               props (mapcar (lambda (kv)
                               (list 'my/redis-elem
                                     (list :kind 'zset :member (car kv) :score (cdr kv))
                                     'my/redis-value (car kv)))
                             pairs))))
      ("stream"
       (let* ((n (my/redis--int (car (my/redis--batch conn db (list (list "XLEN" key)))) 0))
              (entries (car (my/redis--batch
                             conn db
                             (list (list "XREVRANGE" key "+" "-" "COUNT"
                                         (number-to-string limit)))))))
         (when (> n limit) (setq note (format "showing newest %d of %d" limit n)))
         (setq total n cols '("id" "fields")
               rows (mapcar (lambda (e)
                              (list (cons "id" (car e))
                                    (cons "fields" (my/redis--stream-fields (cadr e)))))
                            entries)
               props (mapcar (lambda (e) (list 'my/redis-elem
                                               (list :kind 'stream :id (car e))
                                               'my/redis-value (car e)))
                             entries))))
      (_ (setq note "unsupported type -- use the scratch pad (SPC d R s)")))
    (setq my/redis--key-total total
          my/redis--cols cols
          my/redis--key-meta (list (cons "ttl" ttl) (cons "encoding" enc)))
    (when (and cols my/redis--sort-col)
      (let ((order (my/redis--sort-rows rows my/redis--sort-col my/redis--sort-desc)))
        (setq props (mapcar (lambda (r) (nth (cl-position r rows :test #'eq) props)) order)
              rows order)))
    (setq my/redis--rows rows)
    (erase-buffer)
    (my/redis--header "%s  db %s   key %s" (plist-get conn :name) db
                      (my/redis--escape-controls (format "%s" key)))
    (my/redis--header "type %s   ttl %s   encoding %s%s"
                      type (my/redis--humanise-ttl ttl)
                      (my/redis--cell-display enc)
                      (if total (format "   size %s" total) ""))
    (when note (insert (propertize (format "# %s\n" note) 'face 'warning)))
    (insert "\n")
    (cond
     ((equal type "string") (my/redis--insert-string-value (car rows)))
     ((null cols) (insert "(nothing to show)\n"))
     ((null rows) (insert "(empty)\n"))
     (t (my/redis--insert-grid cols rows props)))
    (goto-char (point-min))))

(defun my/redis--json-string-p (s)
  (and (stringp s)
       (string-match-p "\\`[ \t\n]*[[{]" s)
       ;; :: only whether it PARSES matters -- `{}' parses to nil under
       ;; :: :object-type alist, so the value itself can't be the test
       (condition-case nil
           (progn (ignore (json-parse-string s :object-type 'alist)) t)
         (error nil))))

(defun my/redis--insert-string-value (val)
  ":: Draw a string key's value, pretty-printing it when it is JSON."
  (cond
   ((my/redis--error-p val)
    (insert (my/redis--format-reply val) "\n"))
   ((my/redis--json-string-p val)
    (insert (propertize "# value parses as JSON -- shown pretty-printed\n"
                        'face 'font-lock-comment-face))
    (let ((start (point)))
      (insert val)
      (ignore-errors (json-pretty-print start (point)))
      (put-text-property start (point) 'my/redis-value val))
    (insert "\n"))
   (t
    (let ((start (point)))
      (insert (format "%s" (if (eq val :null) "(nil)" val)))
      (put-text-property start (point) 'my/redis-value val))
    (insert "\n"))))

(defun my/redis--open-key (conn db key)
  ":: Open the inspector for KEY."
  (let ((buf (my/redis--buffer
              (format "Redis %s %s" (plist-get conn :name)
                      (my/redis--sanitise-name (format "%s" key) 50)))))
    (with-current-buffer buf
      (my/redis-result-mode)
      (setq my/redis--conn conn my/redis--db db
            my/redis--view 'key my/redis--key key
            my/redis--limit (or my/redis--limit my/redis-default-limit)
            my/redis--sort-col nil my/redis--sort-desc nil)
      (my/redis--render-key))
    (my/redis--show buf)))

;; ──────────────────────────────────────────────────────
;; :: Replies view (scratch / saved raw runs)
;; ──────────────────────────────────────────────────────

(defun my/redis--render-replies ()
  (let* ((reps (my/redis--pipe my/redis--conn my/redis--db my/redis--lines))
         (inhibit-read-only t))
    (setq my/redis--replies (cl-mapcar #'cons my/redis--lines reps))
    (erase-buffer)
    (my/redis--header "%s  db %s   %d command(s)"
                      (plist-get my/redis--conn :name) my/redis--db
                      (length my/redis--lines))
    (insert "\n")
    (dolist (cr my/redis--replies)
      (insert (propertize (format "> %s\n" (car cr)) 'face 'font-lock-keyword-face))
      (insert (my/redis--format-reply (cdr cr)) "\n\n"))
    (goto-char (point-min))))

(defun my/redis--open-replies (conn db lines title)
  ":: Run LINES and show the replies (used by the scratch pad and saved runs)."
  (let ((buf (my/redis--buffer (my/redis--sanitise-name title 70))))
    (with-current-buffer buf
      (my/redis-result-mode)
      (setq my/redis--conn conn my/redis--db db
            my/redis--view 'replies my/redis--lines lines my/redis--title title)
      (my/redis--render-replies))
    (my/redis--show buf)))

;; ──────────────────────────────────────────────────────
;; :: INFO dashboard
;; ──────────────────────────────────────────────────────

(defun my/redis--parse-info (text)
  ":: INFO's CRLF payload -> list of (SECTION . ((k . v) ...))."
  (let ((section "general") (acc '()) (cur '()))
    (dolist (line (split-string (or text "") "\r?\n"))
      (cond
       ((string-prefix-p "#" line)
        (when cur (push (cons section (nreverse cur)) acc) (setq cur '()))
        (setq section (string-trim (substring line 1))))
       ((string-match "\\`\\([^:]+\\):\\(.*\\)\\'" line)
        (push (cons (match-string 1 line) (match-string 2 line)) cur))))
    (when cur (push (cons section (nreverse cur)) acc))
    (nreverse acc)))

(defun my/redis--render-info ()
  ;; :: INFO is one of the commands redis-cli prints verbatim regardless of
  ;; :: --json, so fetch it as plain text rather than trying to parse a reply.
  (let* ((rep (if my/redis--info-section
                  (my/redis--call-text my/redis--conn my/redis--db
                                       "INFO" my/redis--info-section)
                (my/redis--call-text my/redis--conn my/redis--db "INFO")))
         (inhibit-read-only t))
    (when (string-empty-p (string-trim (or rep "")))
      (user-error "INFO returned nothing"))
    (erase-buffer)
    (my/redis--header "%s  %s:%s   INFO %s   , r refresh   , s section"
                      (plist-get my/redis--conn :name)
                      (plist-get my/redis--conn :host)
                      (plist-get my/redis--conn :port)
                      (or my/redis--info-section "(all)"))
    (insert "\n")
    (dolist (sec (my/redis--parse-info rep))
      (insert (propertize (format "%s\n" (car sec)) 'face 'font-lock-function-name-face))
      (let ((w (apply #'max 1 (mapcar (lambda (kv) (length (car kv))) (cdr sec)))))
        (dolist (kv (cdr sec))
          (insert (format (format "  %%-%ds  %%s\n" w) (car kv) (cdr kv)))))
      (insert "\n"))
    (goto-char (point-min))))

(defun my/redis-info (&optional arg)
  ":: Redis INFO dashboard (SPC d R i). C-u picks one section."
  (interactive "P")
  (let* ((conn (if (and (derived-mode-p 'my/redis-result-mode) my/redis--conn)
                   my/redis--conn
                 (my/redis--read-conn "INFO for: ")))
         (db (or my/redis--db (plist-get conn :db)))
         (section (when arg
                    (completing-read "Section: "
                                     '("server" "clients" "memory" "persistence"
                                       "stats" "replication" "cpu" "commandstats"
                                       "latencystats" "cluster" "keyspace")
                                     nil t)))
         (buf (my/redis--buffer (format "Redis INFO %s" (plist-get conn :name)))))
    (with-current-buffer buf
      (my/redis-result-mode)
      (setq my/redis--conn conn my/redis--db db
            my/redis--view 'info my/redis--info-section section)
      (my/redis--render-info))
    (my/redis--show buf)))

(defun my/redis-info-section ()
  ":: Switch the INFO view to another section (blank = all)."
  (interactive)
  (my/redis--assert-view 'info)
  (let ((s (completing-read "Section (blank = all): "
                            '("server" "clients" "memory" "persistence" "stats"
                              "replication" "cpu" "commandstats" "latencystats"
                              "cluster" "keyspace")
                            nil nil)))
    (setq my/redis--info-section (unless (string-empty-p s) s))
    (my/redis--render-info)))

;; ──────────────────────────────────────────────────────
;; :: Render dispatch + navigation
;; ──────────────────────────────────────────────────────

(defun my/redis--render ()
  ":: Redraw the current buffer from its state."
  (pcase my/redis--view
    ('keys    (my/redis--render-keys))
    ('key     (my/redis--render-key))
    ('replies (my/redis--render-replies))
    ('info    (my/redis--render-info))
    (_ (user-error "Not a Redis view"))))

(defun my/redis-refresh ()
  ":: Re-run the current view."
  (interactive)
  (my/redis--render)
  (message "Refreshed"))

(defun my/redis--rerender-for (conn db)
  ":: Redraw every open keys view bound to CONN/DB (after a write elsewhere)."
  (dolist (b (buffer-list))
    (with-current-buffer b
      (when (and (derived-mode-p 'my/redis-result-mode)
                 (eq my/redis--view 'keys)
                 (equal (plist-get my/redis--conn :name) (plist-get conn :name))
                 (equal my/redis--db db))
        (ignore-errors (my/redis--render-keys))))))

(defun my/redis--key-at-point ()
  (or (get-text-property (point) 'my/redis-key)
      (user-error "No key on this line")))

(defun my/redis-inspect ()
  ":: Inspect the key on this line (RET in a keys view)."
  (interactive)
  (my/redis--assert-view 'keys)
  (let ((k (my/redis--key-at-point)))
    (when (my/redis--error-p k) (user-error "Key is not readable as text"))
    (push (current-buffer) my/redis--nav-stack)
    (my/redis--open-key my/redis--conn my/redis--db k)))

(defun my/redis-inspect-named (key)
  ":: Inspect a key typed by name."
  (interactive "sKey: ")
  (my/redis--assert-view 'keys 'key 'info 'replies)
  (push (current-buffer) my/redis--nav-stack)
  (my/redis--open-key my/redis--conn my/redis--db key))

(defun my/redis-back ()
  ":: Return to the view we drilled in from (C-o)."
  (interactive)
  (let ((buf (pop my/redis--nav-stack)))
    (while (and buf (not (buffer-live-p buf)))
      (setq buf (pop my/redis--nav-stack)))
    (if buf (pop-to-buffer buf) (user-error "Nothing to go back to"))))

(defun my/redis-yank ()
  ":: Copy the key (keys view) or the element value (inspector) at point."
  (interactive)
  (let ((v (or (get-text-property (point) 'my/redis-key)
               (get-text-property (point) 'my/redis-value))))
    (unless v (user-error "Nothing to copy here"))
    (when (my/redis--error-p v) (user-error "Value is not copyable as text"))
    (let ((s (format "%s" v)))
      (kill-new s)
      (gui-set-selection 'CLIPBOARD s)
      (message "Copied → %s" (truncate-string-to-width s 60 nil nil "…")))))

;; ──────────────────────────────────────────────────────
;; :: View controls
;; ──────────────────────────────────────────────────────

(defun my/redis-filter ()
  ":: Set the SCAN MATCH pattern (blank = *)."
  (interactive)
  (my/redis--assert-view 'keys)
  (let ((p (read-string "SCAN pattern: " my/redis--pattern)))
    (setq my/redis--pattern (if (string-empty-p p) "*" p))
    (rename-buffer (my/redis--keys-buffer-name my/redis--conn my/redis--db
                                               my/redis--pattern)
                   t)
    (my/redis--render-keys)))

(defun my/redis-type-filter ()
  ":: Restrict the keys view to one type (blank clears)."
  (interactive)
  (my/redis--assert-view 'keys)
  (let ((ty (completing-read "Type (blank = all): "
                             '("string" "hash" "list" "set" "zset" "stream")
                             nil nil)))
    (setq my/redis--type (unless (string-empty-p ty) ty))
    (my/redis--render-keys)))

(defun my/redis-limit (n)
  ":: Set how many keys / elements are fetched."
  (interactive "nLimit: ")
  (my/redis--assert-view 'keys 'key)
  (setq my/redis--limit (max 1 n))
  (my/redis--render))

(defun my/redis-switch-db (n)
  ":: Point this buffer at another logical db."
  (interactive "nLogical db: ")
  (my/redis--assert-view 'keys 'key 'info)
  (setq my/redis--db n)
  (when (eq my/redis--view 'keys)
    (rename-buffer (my/redis--keys-buffer-name my/redis--conn n my/redis--pattern) t))
  (my/redis--render))

(defun my/redis-sort-column (&optional clear)
  ":: Sort by the column under point; repeat toggles direction, C-u clears."
  (interactive "P")
  (my/redis--assert-view 'keys 'key)
  (if clear
      (progn (setq my/redis--sort-col nil my/redis--sort-desc nil)
             (my/redis--render)
             (message "Sort cleared"))
    (let ((col (get-text-property (point) 'my/redis-col)))
      (unless col (user-error "Move point onto a column to sort by it"))
      (if (equal col my/redis--sort-col)
          (setq my/redis--sort-desc (not my/redis--sort-desc))
        (setq my/redis--sort-col col my/redis--sort-desc nil))
      (my/redis--render)
      (my/redis--goto-column col)
      (message "Sorted by %s %s" col (if my/redis--sort-desc "desc" "asc")))))

;; ──────────────────────────────────────────────────────
;; :: JSON view
;; ──────────────────────────────────────────────────────

(defun my/redis--jsonable (v)
  ":: Coerce a reply value into something `json-serialize' accepts."
  (cond ((eq v :null) :null)
        ((my/redis--error-p v) (format "%s" (cdr v)))
        ((numberp v) v)
        ((stringp v) v)
        ((listp v) (vconcat (mapcar #'my/redis--jsonable v)))
        (t (format "%s" v))))

(defun my/redis-json-view ()
  ":: Show the current view as pretty-printed JSON in a side buffer."
  (interactive)
  (my/redis--assert-view 'keys 'key)
  (let* ((data
          (cond
           ((eq my/redis--view 'keys)
            (vconcat
             (mapcar (lambda (r)
                       ;; :: `json-serialize' wants SYMBOL keys in an alist --
                       ;; :: string keys signal (wrong-type-argument symbolp ...)
                       (mapcar (lambda (c)
                                 (cons (intern c)
                                       (my/redis--jsonable (cdr (assoc c r)))))
                               '("key" "type" "ttl" "size")))
                     my/redis--rows)))
           ((equal my/redis--key-type "string")
            (let ((v (car my/redis--rows)))
              (if (my/redis--json-string-p v)
                  (json-parse-string v :object-type 'alist :array-type 'list)
                (my/redis--jsonable v))))
           (t (vconcat (mapcar (lambda (r)
                                 (mapcar (lambda (kv)
                                           (cons (intern (car kv))
                                                 (my/redis--jsonable (cdr kv))))
                                         r))
                               my/redis--rows)))))
         (buf (get-buffer-create
               (format "*Redis JSON: %s*"
                       (my/redis--sanitise-name
                        (or (and (eq my/redis--view 'key) (format "%s" my/redis--key))
                            my/redis--pattern "view")
                        40)))))
    (with-current-buffer buf
      (cond ((fboundp 'json-mode) (json-mode))
            ((fboundp 'js-json-mode) (js-json-mode))
            (t (js-mode)))
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (json-serialize data :null-object :null :false-object :false))
        (ignore-errors (json-pretty-print-buffer))
        (goto-char (point-min)))
      (view-mode 1))
    (when (fboundp 'persp-add-buffer) (persp-add-buffer buf))
    (display-buffer buf)))


;; ──────────────────────────────────────────────────────
;; :: Writes -- every one of them confirms first.
;; ::
;; :: Unlike the Postgres side there is no transaction to hide behind: Redis has
;; :: MULTI but no rollback-after-the-fact, so a confirmed write is immediately
;; :: durable. That is why every entry point here goes through `y-or-n-p' and why
;; :: FLUSHDB/FLUSHALL are deliberately absent.
;; ──────────────────────────────────────────────────────

(defun my/redis--writable-value (v what)
  ":: V as a string, or an error. Values that came back as raw bytes can't be
   round-tripped through the inline quoter safely, so writes refuse them."
  (cond ((my/redis--error-p v)
         (user-error "%s is not readable as text -- refusing to write" what))
        ((eq v :null) (user-error "%s is nil" what))
        (t (format "%s" v))))

(defun my/redis--elem-at-point ()
  (or (get-text-property (point) 'my/redis-elem)
      (user-error "No element on this line")))

(defun my/redis--elem-label (elem)
  (pcase (plist-get elem :kind)
    ('hash   (format "field %s" (plist-get elem :field)))
    ('list   (format "index %s" (plist-get elem :index)))
    ('set    (format "member %s" (plist-get elem :member)))
    ('zset   (format "member %s" (plist-get elem :member)))
    ('stream (format "entry %s" (plist-get elem :id)))
    (_ "element")))

(defun my/redis--delete-elem-commands (key elem)
  ":: Commands that remove ELEM from KEY."
  (pcase (plist-get elem :kind)
    ('hash   (list (list "HDEL" key (my/redis--writable-value
                                     (plist-get elem :field) "Field"))))
    ('set    (list (list "SREM" key (my/redis--writable-value
                                     (plist-get elem :member) "Member"))))
    ('zset   (list (list "ZREM" key (my/redis--writable-value
                                     (plist-get elem :member) "Member"))))
    ('stream (list (list "XDEL" key (my/redis--writable-value
                                     (plist-get elem :id) "Id"))))
    ;; :: Lists have no delete-by-index. LREM would also remove EQUAL siblings,
    ;; :: so stamp a unique sentinel onto just this index first and remove that.
    ;; :: Wrapped in MULTI/EXEC so a half-applied pair can't leave the sentinel
    ;; :: sitting in the list.
    ('list   (let ((sentinel (format "__RDEL_%s__"
                                     (substring (secure-hash 'sha256
                                                             (format "%s%s" (random)
                                                                     (float-time)))
                                                0 16))))
               (list (list "MULTI")
                     (list "LSET" key (format "%s" (plist-get elem :index)) sentinel)
                     (list "LREM" key "1" sentinel)
                     (list "EXEC"))))
    (_ (user-error "Don't know how to delete from a %s" (plist-get elem :kind)))))

(defun my/redis-delete-at-point ()
  ":: dd -- delete the key (keys view) or the element (inspector) at point."
  (interactive)
  (my/redis--assert-view 'keys 'key)
  (if (eq my/redis--view 'keys)
      (let ((k (my/redis--writable-value (my/redis--key-at-point) "Key")))
        (when (y-or-n-p (format "DEL %s on %s? " k (plist-get my/redis--conn :name)))
          (my/redis--batch my/redis--conn my/redis--db (list (list "DEL" k)))
          (my/redis--render-keys)
          (message "Deleted %s" k)))
    (let* ((elem (my/redis--elem-at-point))
           (cmds (my/redis--delete-elem-commands my/redis--key elem)))
      (when (y-or-n-p (format "Delete %s from %s? "
                              (my/redis--elem-label elem) my/redis--key))
        (my/redis--batch my/redis--conn my/redis--db cmds)
        (my/redis--render-key)
        (message "Deleted %s" (my/redis--elem-label elem))))))

(defun my/redis-delete-region (beg end)
  ":: Visual `d' -- delete every key / element in the selection, one batch."
  (interactive "r")
  (my/redis--assert-view 'keys 'key)
  (let ((items '()))
    (save-excursion
      (goto-char beg)
      (while (< (point) end)
        (let ((v (if (eq my/redis--view 'keys)
                     (get-text-property (point) 'my/redis-key)
                   (get-text-property (point) 'my/redis-elem))))
          (when v (cl-pushnew v items :test #'equal)))
        (forward-line 1)))
    (when (fboundp 'evil-normal-state) (evil-normal-state))
    (unless items (user-error "Nothing selected"))
    (setq items (nreverse items))
    (if (eq my/redis--view 'keys)
        (let ((keys (mapcar (lambda (k) (my/redis--writable-value k "Key")) items)))
          (when (y-or-n-p (format "DEL %d key(s) on %s? "
                                  (length keys) (plist-get my/redis--conn :name)))
            (my/redis--batch my/redis--conn my/redis--db (list (cons "DEL" keys)))
            (my/redis--render-keys)
            (message "Deleted %d key(s)" (length keys))))
      (when (y-or-n-p (format "Delete %d element(s) from %s? "
                              (length items) my/redis--key))
        ;; :: list deletes are index-based, so apply them high-to-low -- removing
        ;; :: a low index would renumber everything above it.
        (let ((ordered (if (equal my/redis--key-type "list")
                           (sort (copy-sequence items)
                                 (lambda (a b) (> (or (plist-get a :index) 0)
                                                  (or (plist-get b :index) 0))))
                         items)))
          (my/redis--batch my/redis--conn my/redis--db
                           (cl-loop for e in ordered
                                    append (my/redis--delete-elem-commands
                                            my/redis--key e))))
        (my/redis--render-key)
        (message "Deleted %d element(s)" (length items))))))

(defun my/redis-delete-key ()
  ":: , D -- delete the whole key being inspected, then close the buffer."
  (interactive)
  (my/redis--assert-view 'key)
  (let ((k (my/redis--writable-value my/redis--key "Key"))
        (conn my/redis--conn) (db my/redis--db)
        (buf (current-buffer)))
    (when (yes-or-no-p (format "DEL the whole key %s on %s? "
                               k (plist-get conn :name)))
      (my/redis--batch conn db (list (list "DEL" k)))
      (quit-window t)
      (when (buffer-live-p buf) (kill-buffer buf))
      (my/redis--rerender-for conn db)
      (message "Deleted %s" k))))

(defun my/redis-set-ttl ()
  ":: , t -- set or clear the inspected key's TTL (blank = PERSIST)."
  (interactive)
  (my/redis--assert-view 'key)
  (let* ((k (my/redis--writable-value my/redis--key "Key"))
         (input (read-string "TTL (30s / 10m / 2h / 1d, blank = persist): "))
         (secs  (my/redis--parse-duration input))
         (cmd   (if secs
                    (list "EXPIRE" k (number-to-string secs))
                  (list "PERSIST" k))))
    (when (y-or-n-p (if secs (format "Expire %s in %s? " k input)
                      (format "Remove the expiry on %s? " k)))
      (let ((rep (car (my/redis--batch my/redis--conn my/redis--db (list cmd)))))
        (when (my/redis--error-p rep) (user-error "%s" (cdr rep))))
      (my/redis--render-key)
      (message (if secs "TTL set" "TTL cleared")))))

(defun my/redis-rename-key ()
  ":: , n -- rename the inspected key, refusing to clobber an existing one."
  (interactive)
  (my/redis--assert-view 'key)
  (let* ((old (my/redis--writable-value my/redis--key "Key"))
         (new (read-string "Rename to: " old)))
    (when (or (string-empty-p new) (equal new old)) (user-error "No change"))
    (when (y-or-n-p (format "Rename %s -> %s? " old new))
      ;; :: RENAMENX, not RENAME: RENAME silently destroys the destination key.
      (let ((rep (car (my/redis--batch my/redis--conn my/redis--db
                                       (list (list "RENAMENX" old new))))))
        (when (my/redis--error-p rep) (user-error "%s" (cdr rep)))
        (when (eql (my/redis--int rep 1) 0)
          (user-error "%s already exists -- not renamed" new)))
      (let ((conn my/redis--conn) (db my/redis--db) (buf (current-buffer)))
        (quit-window t)
        (when (buffer-live-p buf) (kill-buffer buf))
        (my/redis--rerender-for conn db)
        (my/redis--open-key conn db new))
      (message "Renamed to %s" new))))

;; ──────────────────────────────────────────────────────
;; :: Edit form
;; ::
;; :: Unlike the SQL form (db-write.el), the value region is the whole rest of
;; :: the buffer rather than one line, so multi-line values (JSON blobs, and
;; :: they are most of what lives in a Redis string) can be edited naturally.
;; :: The header is read-only; the value starts at `my/redis--edit-start'.
;; ──────────────────────────────────────────────────────

(defvar-local my/redis--edit-conn nil)
(defvar-local my/redis--edit-db nil)
(defvar-local my/redis--edit-key nil)
(defvar-local my/redis--edit-elem nil
  ":: Which element is being edited, or nil for a whole string key.")
(defvar-local my/redis--edit-source nil)
(defvar-local my/redis--edit-start nil)
(defvar-local my/redis--edit-orig nil
  ":: The original value, kept byte-exact so a no-op edit writes nothing.")
(defvar-local my/redis--edit-new nil
  ":: Non-nil when applying should create the key rather than update it.")

(define-derived-mode my/redis-edit-mode fundamental-mode "Redis-Edit"
  ":: Form buffer for one Redis value. Plain buffer, so evil motions all work."
  (setq-local truncate-lines nil))

(defun my/redis--ro (s &optional face)
  ":: Read-only, non-sticky structural text (so typing beside it stays editable)."
  (propertize s 'read-only t 'rear-nonsticky t 'face face))

(defun my/redis--edit-value ()
  ":: Current text of the editable region."
  (buffer-substring-no-properties my/redis--edit-start (point-max)))

(defun my/redis--open-edit (conn db key elem value source &optional new)
  ":: Open the edit form for KEY (whole string) or ELEM within it."
  (let ((buf (get-buffer-create
              (format "*redis-edit %s %s*"
                      (plist-get conn :name)
                      (my/redis--sanitise-name
                       (format "%s%s" key (if elem (concat " " (my/redis--elem-label elem)) ""))
                       50)))))
    (with-current-buffer buf
      (my/redis-edit-mode)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (my/redis--ro
                 (format "# %s %s  db %s%s\n# C-c C-c apply   C-c C-k cancel\n\n"
                         (if new "create" "edit")
                         (my/redis--escape-controls (format "%s" key)) db
                         (if elem (concat "  " (my/redis--elem-label elem)) ""))
                 'font-lock-comment-face))
        (setq my/redis--edit-start (point-marker))
        (set-marker-insertion-type my/redis--edit-start nil)
        (insert (or value "")))
      (setq my/redis--edit-conn conn my/redis--edit-db db
            my/redis--edit-key key my/redis--edit-elem elem
            my/redis--edit-source source my/redis--edit-orig (or value "")
            my/redis--edit-new new)
      (goto-char my/redis--edit-start))
    (when (fboundp 'persp-add-buffer) (persp-add-buffer buf))
    (select-window (display-buffer buf))))

(defun my/redis--set-string (conn db key value ttl)
  ":: SET KEY with KEEPTTL, falling back for servers that lack it (< 6.0)."
  (let ((rep (my/redis--call-stdin conn db value "SET" key "KEEPTTL")))
    (if (and (my/redis--error-p rep)
             (string-match-p "syntax error" (format "%s" (cdr rep))))
        ;; :: pre-6.0: plain SET drops the TTL, so put it back when there was one
        (let ((r2 (my/redis--call-stdin conn db value "SET" key)))
          (when (my/redis--error-p r2) (user-error "%s" (cdr r2)))
          (let ((secs (my/redis--int ttl -1)))
            (when (and secs (> secs 0))
              (my/redis--batch conn db
                               (list (list "EXPIRE" key (number-to-string secs)))))))
      (when (my/redis--error-p rep) (user-error "%s" (cdr rep))))))

(cl-defun my/redis-edit-apply ()
  ":: C-c C-c -- write the form back."
  (interactive)
  (let* ((conn my/redis--edit-conn) (db my/redis--edit-db)
         (key my/redis--edit-key)   (elem my/redis--edit-elem)
         (src my/redis--edit-source)
         (new (my/redis--edit-value)))
    (when (and (not my/redis--edit-new) (equal new my/redis--edit-orig))
      (message "No changes")
      (cl-return-from my/redis-edit-apply (my/redis-edit-abort)))
    (pcase (and elem (plist-get elem :kind))
      ('nil  ;; :: whole string key
       (my/redis--set-string conn db key new
                             (cdr (assoc "ttl" (and (buffer-live-p src)
                                                    (buffer-local-value
                                                     'my/redis--key-meta src))))))
      ('hash (let ((r (my/redis--call-stdin conn db new "HSET" key
                                            (format "%s" (plist-get elem :field)))))
               (when (my/redis--error-p r) (user-error "%s" (cdr r)))))
      ('list (let ((r (my/redis--call-stdin conn db new "LSET" key
                                            (format "%s" (plist-get elem :index)))))
               (when (my/redis--error-p r) (user-error "%s" (cdr r)))))
      ('zset (let* ((score (read-string "Score: " (format "%s" (or (plist-get elem :score) 0))))
                    (r (my/redis--call-stdin conn db new "ZADD" key score)))
               (when (my/redis--error-p r) (user-error "%s" (cdr r)))
               ;; :: ZADD adds under the new member name; drop the old one
               (let ((old (plist-get elem :member)))
                 (unless (equal (format "%s" old) new)
                   (my/redis--batch conn db (list (list "ZREM" key (format "%s" old))))))))
      ('set  ;; :: sets have no in-place update -- swap old for new atomically
       (let ((old (format "%s" (plist-get elem :member))))
         (my/redis--batch conn db
                          (list (list "MULTI")
                                (list "SREM" key old)
                                (list "SADD" key new)
                                (list "EXEC")))))
      ('stream (user-error "Stream entries are immutable -- delete and re-add"))
      (kind (user-error "Don't know how to edit a %s" kind)))
    (my/redis--finish-edit src (if my/redis--edit-new "Created" "Updated"))))

(defun my/redis--finish-edit (source verb)
  ":: Refresh the view we came from, close the form, restore the layout."
  (when (buffer-live-p source)
    (with-current-buffer source (ignore-errors (my/redis--render))))
  (quit-window t)
  (message "%s" verb))

(defun my/redis-edit-abort ()
  ":: Discard the form without writing."
  (interactive)
  (quit-window t))

(defun my/redis-edit ()
  ":: , e -- edit the value at point. In a keys view this drills into the key
   first, since what `edit' means depends on its type."
  (interactive)
  (my/redis--assert-view 'keys 'key)
  (if (eq my/redis--view 'keys)
      (my/redis-inspect)
    (pcase my/redis--key-type
      ("string"
       (my/redis--open-edit my/redis--conn my/redis--db my/redis--key nil
                            (my/redis--writable-value (car my/redis--rows) "Value")
                            (current-buffer)))
      ("stream" (user-error "Stream entries are immutable"))
      (_
       ;; :: `my/redis-value' is set per row to whatever the edit target is:
       ;; :: the hash field's value, the list element, the set/zset member.
       (let* ((elem (my/redis--elem-at-point))
              (val  (get-text-property (point) 'my/redis-value)))
         (my/redis--open-edit my/redis--conn my/redis--db my/redis--key elem
                              (my/redis--writable-value val "Value")
                              (current-buffer)))))))

(defun my/redis-insert ()
  ":: , i -- add a key (keys view) or an element (inspector)."
  (interactive)
  (my/redis--assert-view 'keys 'key)
  (if (eq my/redis--view 'keys)
      (let* ((key (read-string "New key: "))
             (type (completing-read "Type: "
                                    '("string" "hash" "list" "set" "zset") nil t)))
        (when (string-empty-p key) (user-error "No key name"))
        (if (equal type "string")
            (my/redis--open-edit my/redis--conn my/redis--db key nil ""
                                 (current-buffer) t)
          (let* ((member (read-string (pcase type
                                        ("hash" "Field: ")
                                        ("zset" "Member: ")
                                        (_ "Value: "))))
                 (value (pcase type
                          ("hash" (read-string "Value: "))
                          ("zset" (read-string "Score: " "0"))
                          (_ nil)))
                 (cmd (pcase type
                        ("hash" (list "HSET" key member value))
                        ("list" (list "RPUSH" key member))
                        ("set"  (list "SADD" key member))
                        ("zset" (list "ZADD" key value member)))))
            (let ((r (car (my/redis--batch my/redis--conn my/redis--db (list cmd)))))
              (when (my/redis--error-p r) (user-error "%s" (cdr r))))
            (my/redis--render-keys)
            (message "Created %s" key))))
    (let* ((type my/redis--key-type)
           (key  my/redis--key)
           (member (read-string (pcase type
                                  ("hash" "Field: ")
                                  ("zset" "Member: ")
                                  ("string" "Append: ")
                                  (_ "Value: "))))
           (value (pcase type
                    ("hash" (read-string "Value: "))
                    ("zset" (read-string "Score: " "0"))
                    (_ nil)))
           (cmd (pcase type
                  ("hash"   (list "HSET" key member value))
                  ("list"   (list "RPUSH" key member))
                  ("set"    (list "SADD" key member))
                  ("zset"   (list "ZADD" key value member))
                  ("string" (list "APPEND" key member))
                  (_ (user-error "Can't insert into a %s" type)))))
      (let ((r (car (my/redis--batch my/redis--conn my/redis--db (list cmd)))))
        (when (my/redis--error-p r) (user-error "%s" (cdr r))))
      (my/redis--render-key)
      (message "Added"))))

;; ──────────────────────────────────────────────────────
;; :: Bulk cleanup -- these buffers have no earmuffs (so they show up in SPC ,),
;; :: which means they pile up. Same reasoning as my/sql-kill-all-buffers.
;; ──────────────────────────────────────────────────────

(defun my/redis-kill-all-buffers (&optional include-scratch)
  ":: Kill every transient Redis buffer (SPC d R K). C-u also kills the pad."
  (interactive "P")
  (let ((bufs (cl-remove-if-not
               (lambda (buf)
                 (with-current-buffer buf
                   (or (derived-mode-p 'my/redis-result-mode 'my/redis-edit-mode)
                       (string-match-p "\\`\\*[Rr]edis[- ]" (buffer-name))
                       (and include-scratch (equal (buffer-name) "*redis-scratch*")))))
               (buffer-list))))
    (if (null bufs)
        (message "No Redis buffers to kill")
      (when (yes-or-no-p (format "Kill %d Redis buffer%s? "
                                 (length bufs) (if (cdr bufs) "s" "")))
        (mapc #'kill-buffer bufs)
        (message "Killed %d Redis buffer%s"
                 (length bufs) (if (cdr bufs) "s" ""))))))

;; ──────────────────────────────────────────────────────
;; :: Keys -- localleader letters match the DB result buffer wherever the
;; :: concept exists (f/l/r/S/j/e/i/s), with Redis-only ones on top.
;; ──────────────────────────────────────────────────────

(map! :map my/redis-result-mode-map
      :n "q"      #'quit-window
      :n "RET"    #'my/redis-inspect
      :n [return] #'my/redis-inspect
      :n "C-o"    #'my/redis-back
      :n "y"      #'my/redis-yank
      :n "dd"     #'my/redis-delete-at-point
      :v "d"      #'my/redis-delete-region
      :localleader
      :desc "Filter (SCAN pattern)" "f" #'my/redis-filter
      :desc "Set limit"             "l" #'my/redis-limit
      :desc "Refresh"               "r" #'my/redis-refresh
      :desc "Sort column"           "S" #'my/redis-sort-column
      :desc "JSON view"             "j" #'my/redis-json-view
      :desc "Edit value"            "e" #'my/redis-edit
      :desc "Insert"                "i" #'my/redis-insert
      :desc "Save command"          "s" #'my/redis-save-command
      :desc "Type filter"           "T" #'my/redis-type-filter
      :desc "Switch db"             "d" #'my/redis-switch-db
      :desc "Inspect key by name"   "k" #'my/redis-inspect-named
      :desc "Set TTL"               "t" #'my/redis-set-ttl
      :desc "Rename key"            "n" #'my/redis-rename-key
      :desc "Delete whole key"      "D" #'my/redis-delete-key
      :desc "INFO"                  "I" #'my/redis-info
      ;; :: `s' is save everywhere in this family, so the INFO section picker
      ;; :: gets its own letter rather than shadowing it in one view.
      :desc "INFO section"          "c" #'my/redis-info-section)

(map! :map my/redis-edit-mode-map
      :n "q"    #'my/redis-edit-abort
      "C-c C-c" #'my/redis-edit-apply
      "C-c C-k" #'my/redis-edit-abort)

(provide 'my-redis-browser)
