;;; modules/redis.el -*- lexical-binding: t; -*-

;; :: Redis from inside Emacs -- connections, the redis-cli runner, batching,
;; :: a command scratch pad and a REPL. The buffer UI lives in redis-browser.el
;; :: and saved commands in redis-saved.el; this file is the `db.el' of the trio.
;; ::
;; ::   SPC d R b    browse keys (SCAN grid)      SPC d R i    INFO dashboard
;; ::   SPC d R s    command scratch pad          SPC d R c    redis-cli REPL (vterm)
;; ::   SPC d R r    reload connections           SPC d R K    kill all redis buffers
;; ::   SPC d R w    save command                 SPC d R q    run saved
;; ::   SPC d R d    delete saved
;; ::
;; :: In the scratch pad:  , r run (region or line)   , c connection   , d db   , w save
;; ::
;; :: Connections come from ~/.authinfo.gpg, one source of truth (same idea as
;; :: db.el). A redis entry is marked by the custom `redis' token, whose value is
;; :: the logical db index:
;; ::
;; ::   machine localhost port 6379 login default password SECRET redis 0 name local-redis
;; ::
;; :: `name' is an optional friendly alias. The token has no `/', so db.el's
;; :: host/db heuristic skips these entries and we skip its entries by requiring
;; :: `redis'. OMIT `password' ENTIRELY for a no-auth server -- see the runner.

(require 'auth-source)
(require 'cl-lib)
(require 'json)
(require 'subr-x)

;; ──────────────────────────────────────────────────────
;; :: Knobs
;; ──────────────────────────────────────────────────────

(defvar my/redis-cli-program "redis-cli"
  ":: redis-cli binary, resolved on PATH at call time. Needs >= 7 for `--json'
   with `-2' (RESP2). `brew install redis' provides it.")

(defvar my/redis-repl-program "redis-cli"
  ":: Binary `my/redis-repl' launches in a vterm. Set to \"iredis\" for the
   fancier interactive client (it can't be used for the runner -- it has no
   machine-readable output mode).")

(defvar my/redis-wallet "~/.authinfo.gpg"
  ":: Netrc-format wallet redis connections are read from.")

(defvar my/redis-timeout 10
  ":: Seconds Emacs waits for a redis-cli invocation before killing it.
   This is the REAL bound -- see `my/redis--run'.")

(defvar my/redis-socket-timeout 30
  ":: Value passed to redis-cli's `-t'. NOT a connect timeout: it is the socket
   READ timeout too, so a small value aborts a legitimately slow SCAN/KEYS and
   leaves the connection desynced. Kept generous on purpose; `my/redis-timeout'
   is what actually bounds us.")

(defvar my/redis-scan-count 500
  ":: COUNT hint per SCAN call (a hint, not a limit -- Redis may return more).")

(defvar my/redis-scan-max-calls 100
  ":: Cap on SCAN round trips per render, so a huge keyspace can't spin forever.
   Hitting it marks the view as a partial scan.")

(defvar my/redis-default-limit 500
  ":: Default number of keys (browser) / elements (inspector) fetched per view.")

(defvar my/redis-max-col-width 60
  ":: Widest a grid column may get before values are truncated with an ellipsis.")

(defvar my/redis-value-max-chars 200000
  ":: Longest string value fetched whole; beyond this the inspector GETRANGEs a
   prefix and marks it truncated.")

;; ──────────────────────────────────────────────────────
;; :: Connections -- derived from the wallet
;; ──────────────────────────────────────────────────────

(defvar my/redis-connection-alist nil
  ":: List of plists (:name :host :port :user :db). Built from the wallet by
   `my/redis-reload-connections'; can also be set directly (tests, batch mode).")

(defun my/redis--connections-from-authinfo ()
  ":: Parse the wallet into connection plists. Only entries carrying the custom
   `redis' token are ours; its value is the logical db index."
  (let (acc)
    (dolist (e (ignore-errors
                 (auth-source-netrc-parse-all (expand-file-name my/redis-wallet))))
      (let ((machine (cdr (assoc "machine" e)))
            (dbtok   (cdr (assoc "redis"   e))))
        (when (and machine dbtok)
          (let* ((port  (string-to-number (or (cdr (assoc "port" e)) "6379")))
                 (db    (string-to-number dbtok))
                 (user  (cdr (assoc "login" e)))
                 (alias (cdr (assoc "name"  e)))
                 (name  (or alias (format "%s:%d/%d" machine port db))))
            (push (list :name name :host machine :port (if (zerop port) 6379 port)
                        :user user :db db)
                  acc)))))
    (nreverse acc)))

(defun my/redis-reload-connections ()
  ":: Re-read connections from the wallet (SPC d R r)."
  (interactive)
  (setq my/redis-connection-alist (my/redis--connections-from-authinfo))
  (message "Loaded %d redis connection(s)" (length my/redis-connection-alist)))

(defun my/redis--ensure-connections ()
  ":: Populate on first use, so the gpg prompt only happens when needed."
  (unless my/redis-connection-alist (my/redis-reload-connections)))

(defun my/redis--conn-by-name (name)
  ":: Connection plist for NAME, or a `user-error'."
  (or (cl-find name my/redis-connection-alist
               :key (lambda (c) (plist-get c :name)) :test #'equal)
      (user-error "No redis connection named %s" name)))

(defun my/redis--conn-annotation (name)
  ":: Dimmed `host:port db N' suffix for the connection picker."
  (let ((c (cl-find name my/redis-connection-alist
                    :key (lambda (x) (plist-get x :name)) :test #'equal)))
    (when c
      (propertize (format "   %s:%s db%s"
                          (plist-get c :host) (plist-get c :port) (plist-get c :db))
                  'face 'shadow))))

(defun my/redis--read-conn (&optional prompt)
  ":: Pick a connection interactively; returns its plist."
  (my/redis--ensure-connections)
  (unless my/redis-connection-alist
    (user-error "No redis connections in %s -- add a `redis' token entry"
                my/redis-wallet))
  (let ((completion-extra-properties
         (list :annotation-function #'my/redis--conn-annotation)))
    (my/redis--conn-by-name
     (completing-read (or prompt "Redis connection: ")
                      (mapcar (lambda (c) (plist-get c :name))
                              my/redis-connection-alist)
                      nil t))))

(defun my/redis--password (conn)
  ":: Password for CONN from the wallet. `:port' disambiguates it from other
   bare-host entries (email, tokens) sharing the same machine."
  (let* ((found  (car (auth-source-search
                       :host (plist-get conn :host)
                       :port (number-to-string (plist-get conn :port))
                       :user (plist-get conn :user)
                       :max 1)))
         (secret (and found (plist-get found :secret))))
    (when secret (if (functionp secret) (funcall secret) secret))))

;; ──────────────────────────────────────────────────────
;; :: Which connection a buffer talks to. Declared HERE, in the base file, so
;; :: the scratch pad (below) and the result buffers (redis-browser.el) share
;; :: one pair of buffer-locals regardless of load order.
;; ──────────────────────────────────────────────────────

(defvar-local my/redis--conn nil
  ":: Connection plist this buffer runs against.")

(defvar-local my/redis--db nil
  ":: Logical db index this buffer runs against (nil = the connection's own).")

;; ──────────────────────────────────────────────────────
;; :: CLI discovery
;; ──────────────────────────────────────────────────────

(defun my/redis--program ()
  ":: Absolute path to redis-cli, or a clear error."
  (or (executable-find my/redis-cli-program)
      (user-error "%s not found on PATH -- `brew install redis'"
                  my/redis-cli-program)))

(defvar my/redis--features nil
  ":: Cached result of `my/redis--cli-features'.")

(defun my/redis--cli-features ()
  ":: Plist (:version :connect-timeout-p) probed once per session.
   `--json' only emits flat RESP2 arrays with `-2', which needs redis-cli >= 7."
  (or my/redis--features
      (let* ((prog (my/redis--program))
             (ver  (string-trim
                    (with-temp-buffer
                      (ignore-errors (call-process prog nil t nil "--version"))
                      (buffer-string))))
             (help (with-temp-buffer
                     (ignore-errors (call-process prog nil t nil "--help"))
                     (buffer-string)))
             (major (when (string-match "\\([0-9]+\\)\\.[0-9]+" ver)
                      (string-to-number (match-string 1 ver)))))
        (unless (and major (>= major 7))
          (user-error "redis-cli >= 7 required for --json -2 (found %s) -- brew install redis"
                      (if (string-empty-p ver) "unknown" ver)))
        (setq my/redis--features
              (list :version ver
                    :connect-timeout-p (and (string-match-p "-t <timeout>" help) t))))))

;; ──────────────────────────────────────────────────────
;; :: The runner
;; ::
;; :: Why `make-process' and not `call-process' (db.el's choice): a C-level
;; :: `call-process' can't be interrupted, which is why db.el has to push its
;; :: timeout down into libpq via PGCONNECT_TIMEOUT. `make-process' + an
;; :: `accept-process-output' loop keeps C-g working, so the Emacs-side deadline
;; :: is a real bound and redis-cli's own `-t' can stay generous.
;; ::
;; :: Why a separate stderr pipe: redis-cli puts EVERY reply on stdout and EVERY
;; :: diagnostic (`Could not connect', `AUTH failed', a mid-batch reconnect) on
;; :: stderr. Merging them and grepping stdout would both lose that split and
;; :: false-positive on real data -- a cached value whose text happens to BE
;; :: "Could not connect to Redis at ..." is exactly the kind of thing that lives
;; :: in a Redis cache. Keeping the streams apart makes the check trivial:
;; :: non-empty stderr => this invocation is untrustworthy.
;; ──────────────────────────────────────────────────────

(defun my/redis--environment (conn pass)
  ":: `process-environment' for a redis-cli call.
   When there is no password the auth vars are actively REMOVED, not merely
   left unset: an ambient REDISCLI_AUTH in the user's environment makes
   redis-cli send AUTH to a no-password server, which fails fatally."
  (ignore conn)
  (let ((base (cl-remove-if
               (lambda (s) (string-match-p "\\`REDISCLI_AUTH\\(_USER\\)?=" s))
               process-environment)))
    (if pass (cons (concat "REDISCLI_AUTH=" pass) base) base)))

(defun my/redis--run (conn db args &optional stdin no-json)
  ":: Run redis-cli against CONN/DB with ARGS, optionally feeding STDIN.
   Returns a plist (:exit N :out TEXT :err TEXT). Never parses -- callers do.
   NO-JSON drops `--json' for the handful of commands redis-cli prints verbatim
   anyway (see `my/redis--call-text')."
  (let* ((prog (my/redis--program))
         (feat (my/redis--cli-features))
         (host (plist-get conn :host))
         (port (number-to-string (plist-get conn :port)))
         (user (plist-get conn :user))
         (pass (my/redis--password conn))
         (dbn  (number-to-string (or db (plist-get conn :db) 0)))
         (cmd  (append (list prog "-h" host "-p" port "-n" dbn)
                       (when (plist-get feat :connect-timeout-p)
                         (list "-t" (number-to-string my/redis-socket-timeout)))
                       ;; :: --user only matters alongside a password (it selects
                       ;; :: which ACL user the AUTH is for); without one there is
                       ;; :: no AUTH at all and passing it just breaks Redis < 6.
                       (when (and pass user) (list "--user" user))
                       (if no-json (list "-2") (list "-2" "--json"))
                       args))
         (process-environment (my/redis--environment conn pass))
         (out "") (err "")
         proc errproc exit)
    (unwind-protect
        (progn
          ;; :: The stderr pipe is created EXPLICITLY: `delete-process' on the
          ;; :: main process does not reap an implicitly-made one, which would
          ;; :: leak a process per query.
          (setq errproc (make-pipe-process
                         :name " *redis-cli-err*"
                         :buffer nil
                         :noquery t
                         :coding '(utf-8-unix . utf-8-unix)
                         :filter (lambda (_p s) (setq err (concat err s)))))
          (setq proc (make-process
                      :name "redis-cli"
                      :buffer nil
                      :command cmd
                      :connection-type 'pipe
                      :coding '(utf-8-unix . utf-8-unix)
                      :noquery t
                      :stderr errproc
                      ;; :: Pure accumulator: `process-send-string' on a full pipe
                      ;; :: can re-enter this filter mid-send, so it must not
                      ;; :: signal or switch buffers.
                      :filter (lambda (_p s) (setq out (concat out s)))))
          ;; :: The EOF is mandatory -- piped redis-cli reads stdin until EOF
          ;; :: and a trailing newline is not one, so without it every batch
          ;; :: would block until the deadline. Sent UNCONDITIONALLY: a one-shot
          ;; :: call passes its command in argv and never reads stdin, but
          ;; :: closing the pipe anyway means nothing downstream can ever wait
          ;; :: on input we are never going to send. The process may already be
          ;; :: dead by now, hence the `condition-case'.
          (condition-case nil
              (progn (when stdin (process-send-string proc stdin))
                     (process-send-eof proc))
            (error nil))
          (let ((deadline (+ (float-time) my/redis-timeout)))
            (while (and (process-live-p proc) (< (float-time) deadline))
              (accept-process-output proc 0.1))
            (when (process-live-p proc)
              (user-error "redis-cli timed out after %ds on %s"
                          my/redis-timeout (plist-get conn :name))))
          ;; :: `process-live-p' going nil does not mean Emacs has read the last
          ;; :: chunk, and stderr can trail the main process -- drain both.
          (let ((until (+ (float-time) 0.5)))
            (while (and (< (float-time) until)
                        (or (accept-process-output proc 0 50 t)
                            (accept-process-output errproc 0 50 t)))))
          (setq exit (process-exit-status proc))
          (list :exit exit :out out :err err))
      (when (process-live-p proc)    (ignore-errors (delete-process proc)))
      (when (process-live-p errproc) (ignore-errors (delete-process errproc)))
      ;; :: `make-pipe-process' still materialises a buffer for the pipe even
      ;; :: with :buffer nil, and deleting the process doesn't reap it. Same
      ;; :: housekeeping as my/sql--txn-teardown.
      (let ((eb (and errproc (process-buffer errproc))))
        (when (buffer-live-p eb) (ignore-errors (kill-buffer eb)))))))

(defun my/redis--check (res conn)
  ":: Signal if RES carries a diagnostic. Non-empty stderr is the single gate:
   it also catches the silent mid-batch reconnect, where redis-cli drops the
   connection, re-SELECTs, exits 0, and quietly loses one stdout line."
  (let ((err (string-trim (plist-get res :err))))
    (unless (string-empty-p err)
      (user-error "redis-cli [%s]: %s"
                  (plist-get conn :name)
                  (car (split-string err "\n" t))))
    res))

;; ──────────────────────────────────────────────────────
;; :: Reply parsing
;; ::
;; :: `--json' prints exactly one line per reply for every RESP2 type -- values
;; :: containing newlines are escaped inside the JSON string, so a line is never
;; :: split. Two things in that output are NOT valid JSON:
;; ::   error:"MSG"          a top-level error reply
;; ::   [..,error:"MSG"]     an error nested inside an array (MULTI/EXEC)
;; :: and bytes >= 0x80 pass through raw, so a binary value is unparsable too.
;; ──────────────────────────────────────────────────────

(defun my/redis--error-message (rest)
  ":: Decode the quoted message trailing an `error:' line."
  (or (ignore-errors (json-parse-string rest)) (string-trim rest)))

(defun my/redis--parse-line (line)
  ":: Parse one redis-cli --json output LINE into a Lisp value or a tagged cons:
   (:error . MSG) (:partial-error . LINE) (:binary . LINE) (:raw . LINE)."
  (if (string-prefix-p "error:" line)
      (cons :error (my/redis--error-message (substring line 6)))
    (condition-case nil
        (json-parse-string line
                           :array-type 'list
                           :null-object :null
                           :false-object :false)
      ;; :: A raw byte that survived utf-8 decoding as an eight-bit char lands
      ;; :: here. `encode-coding-string' recovers the original byte later, which
      ;; :: is why the value is kept as-is rather than dropped.
      (json-utf8-decode-error (cons :binary line))
      ;; :: Only reached when the line failed to parse, so the nested-error test
      ;; :: cannot false-positive: inside a real JSON string the quote would be
      ;; :: escaped (`,error:\"'), not bare.
      (json-error (if (string-match-p "[][,]error:\"" line)
                      (cons :partial-error line)
                    (cons :raw line)))
      (error (cons :raw line)))))

(defun my/redis--error-p (v)
  ":: Non-nil when V is any flavour of failed reply.
   `:text' is deliberately absent -- a verbatim multi-line payload is data."
  (and (consp v) (memq (car v) '(:error :partial-error :raw :no-reply))))

(defun my/redis--pairs (flat)
  ":: Flat (k1 v1 k2 v2 ...) reply -> alist. HGETALL, ZRANGE .. WITHSCORES and
   the *SCAN families all return pairs this way under RESP2."
  (let (acc)
    (while (and (consp flat) (cdr flat))
      (push (cons (car flat) (cadr flat)) acc)
      (setq flat (cddr flat)))
    (nreverse acc)))

(defun my/redis--int (v &optional default)
  ":: V as an integer when it plausibly is one, else DEFAULT."
  (cond ((integerp v) v)
        ((floatp v) (truncate v))
        ((and (stringp v) (string-match-p "\\`-?[0-9]+\\'" v)) (string-to-number v))
        (t default)))

;; ──────────────────────────────────────────────────────
;; :: Argument quoting
;; ::
;; :: Batched commands go over stdin as inline text, which redis-cli splits with
;; :: `sdssplitargs'. Every argument is emitted as a fully-escaped quoted string,
;; :: so keys/values containing spaces, quotes, newlines, UTF-8 or raw bytes all
;; :: survive byte-exactly. Verified round-trip: \x00, ", \, "", \x7f\xff, UTF-8,
;; :: and a literal \x41 sitting in the data.
;; ──────────────────────────────────────────────────────

(defun my/redis--quote-arg (s)
  ":: Encode S as a double-quoted redis-cli inline argument."
  (let ((bytes (encode-coding-string (or s "") 'utf-8 t))
        (acc '()))
    (dotimes (i (length bytes))
      (let ((b (aref bytes i)))
        (push (cond
               ((= b ?\") "\\\"")
               ;; :: Doubling a backslash is what keeps a LITERAL \x41 in the
               ;; :: data safe (it becomes \ + x41). It looks redundant next to
               ;; :: the \xHH rule below; it isn't.
               ((= b ?\\) "\\\\")
               ((and (>= b #x20) (<= b #x7e)) (char-to-string b))
               ;; :: Everything else hex-escaped -- notably 0x0a, which as a
               ;; :: literal would split the command across two input lines.
               (t (format "\\x%02x" b)))
              acc)))
    (concat "\"" (apply #'concat (nreverse acc)) "\"")))

(defun my/redis--command-line (args)
  ":: ARGS (list of strings) as one inline redis-cli command line.
   Joined with EXACTLY one space: `sdssplitargs' requires whitespace or
   end-of-line after a closing quote, so \"a\"\"b\" is rejected outright."
  (mapconcat #'my/redis--quote-arg args " "))

;; ──────────────────────────────────────────────────────
;; :: Batching
;; ::
;; :: A piped redis-cli runs its repl loop, and its stdout line count does NOT
;; :: track the command count. Verified desyncs: a blank line emits nothing;
;; :: `exit'/`quit' silently truncate the rest of the batch; `help' emits ~11
;; :: lines; an `N CMD' repeat prefix bails out early on error. Some of those
;; :: cancel arithmetically, so counting replies can pass while the data is
;; :: misattributed.
;; ::
;; :: So each command is delimited by an `ECHO <nonce><i>' sentinel, which gives
;; :: per-command ATTRIBUTION rather than whole-batch detection: one desynced
;; :: command becomes one (:no-reply) slot and the rest still render. This is the
;; :: same call db-write.el's `my/sql--txn-raw' already made for psql, whose
;; :: comment documents abandoning output-grepping for exactly this reason.
;; ──────────────────────────────────────────────────────

(defconst my/redis--rejected-commands
  '("exit" "quit" "help" "?" "clear" "connect" "subscribe" "psubscribe"
    "ssubscribe" "monitor" "blpop" "brpop" "blmove" "brpoplpush" "blmpop"
    "bzpopmin" "bzpopmax" "bzmpop" "wait" "waitaof")
  ":: Commands refused before spawning. The first group is intercepted by
   redis-cli's own repl (`exit' silently swallows the rest of the batch); the
   rest stream or block forever and would only ever hit the timeout.")

(defun my/redis--line-command (line)
  ":: Lowercased first word of an inline command LINE, quotes stripped."
  (let ((w (car (split-string (string-trim line) "[ \t]+" t))))
    (downcase (replace-regexp-in-string "\\`\"\\|\"\\'" "" (or w "")))))

(defun my/redis--check-lines (lines)
  ":: Refuse batch LINES redis-cli would mishandle, with a reason."
  (dolist (l lines)
    (let ((c (my/redis--line-command l)))
      (when (member c my/redis--rejected-commands)
        (user-error "%s can't be run here -- it %s"
                    (upcase c)
                    (if (member c '("exit" "quit" "help" "?" "clear" "connect"))
                        "is intercepted by redis-cli's own prompt"
                      "blocks or streams forever (use SPC d R c for a REPL)")))
      (when (and (member c '("xread" "xreadgroup"))
                 (string-match-p "\\_<[Bb][Ll][Oo][Cc][Kk]\\_>" l))
        (user-error "XREAD ... BLOCK blocks forever (use SPC d R c for a REPL)"))
      (when (string-match-p "\\`[0-9]+[ \t]" (string-trim l))
        (user-error "Leading count is a redis-cli repeat prefix -- write the command out %s times"
                    (car (split-string (string-trim l) "[ \t]+" t)))))))

(defun my/redis--segments (lines)
  ":: Group LINES into sentinel-delimited segments. A MULTI..EXEC span becomes
   ONE segment because ECHO returns QUEUED inside a transaction and so can't
   delimit it; replies within such a span are aligned by count instead."
  (let ((segs '()) (cur '()) (in-multi nil))
    (dolist (l lines)
      (let ((c (my/redis--line-command l)))
        (push l cur)
        (cond
         ((equal c "multi") (setq in-multi t))
         ((and in-multi (equal c "exec"))
          (setq in-multi nil)
          (push (nreverse cur) segs) (setq cur '()))
         ((not in-multi)
          (push (nreverse cur) segs) (setq cur '())))))
    (when cur (push (nreverse cur) segs))   ;; :: unterminated MULTI
    (nreverse segs)))

(defun my/redis--pipe (conn db lines)
  ":: Run LINES (pre-quoted inline command strings) as one batch on CONN/DB.
   Returns one parsed reply per command, in order; a command whose reply went
   missing yields (:no-reply) without spoiling its neighbours."
  (let* ((lines (cl-remove-if (lambda (l)
                                (string-match-p "\\`[ \t]*\\(#.*\\)?\\'" l))
                              lines)))
    (when (null lines) (user-error "No commands to run"))
    (my/redis--check-lines lines)
    (let* ((nonce (format "__RDONE_%s_"
                          (substring (secure-hash 'sha256
                                                  (format "%s:%s:%s" (random)
                                                          (float-time) (emacs-pid)))
                                     0 16)))
           (mark  (lambda (i) (format "%s%d" nonce i)))
           (segs  (my/redis--segments lines))
           (stdin (let ((acc (list (my/redis--command-line
                                    (list "ECHO" (funcall mark 0)))))
                        (i 0))
                    (dolist (seg segs)
                      (setq acc (append acc seg))
                      (setq i (1+ i))
                      (setq acc (append acc (list (my/redis--command-line
                                                   (list "ECHO" (funcall mark i)))))))
                    (concat (string-join acc "\n") "\n")))
           (res   (my/redis--check (my/redis--run conn db nil stdin) conn))
           ;; :: NOT `lines' -- that name is already the COMMAND lines above,
           ;; :: and shadowing it silently breaks the post-condition assert.
           (rawout (vconcat (split-string (plist-get res :out) "\n" t)))
           (n     (length rawout))
           (pos   0)
           (out   '()))
      ;; :: Walk the RAW lines, comparing each against the sentinel's printed
      ;; :: form. The nonce is alphanumeric, so its --json rendering is just the
      ;; :: marker in double quotes -- an exact `equal' on the whole line, never
      ;; :: a regexp, so no stored value can impersonate a sentinel.
      (cl-flet ((sentinel (i) (concat "\"" (funcall mark i) "\"")))
        (while (and (< pos n) (not (equal (aref rawout pos) (sentinel 0))))
          (setq pos (1+ pos)))
        (setq pos (1+ pos))
        (let ((i 0))
          (dolist (seg segs)
            (setq i (1+ i))
            (let ((want (sentinel i)) (acc '()))
              (while (and (< pos n) (not (equal (aref rawout pos) want)))
                (push (aref rawout pos) acc)
                (setq pos (1+ pos)))
              (setq pos (1+ pos))         ;; :: step over the sentinel itself
              (setq acc (nreverse acc))
              (if (and (= (length seg) 1) (> (length acc) 1))
                  ;; :: One command, many lines: redis-cli forces RAW output for
                  ;; :: INFO, CLIENT LIST/INFO, MEMORY/LATENCY DOCTOR and LOLWUT,
                  ;; :: ignoring --json, so their payload arrives unquoted across
                  ;; :: many lines. Keep it whole as verbatim text instead of
                  ;; :: silently reporting only the first line.
                  (push (cons :text (string-join acc "\n")) out)
                ;; :: Otherwise pad/truncate to the segment's command count: 1
                ;; :: for a plain command, the queue length for a MULTI..EXEC.
                (dotimes (k (length seg))
                  (push (if (nth k acc)
                            (my/redis--parse-line (nth k acc))
                          '(:no-reply))
                        out)))))))
      (setq out (nreverse out))
      ;; :: Cheap post-condition -- catches a bug in the walk above, not in redis.
      (cl-assert (= (length out) (length lines)) nil
                 "redis batch desync: %d replies for %d commands"
                 (length out) (length lines))
      out)))

(defun my/redis--batch (conn db commands)
  ":: Run COMMANDS (a list of arg-lists) as one batch; one reply each."
  (my/redis--pipe conn db (mapcar #'my/redis--command-line commands)))

(defun my/redis--call (conn db &rest args)
  ":: One-shot redis-cli call; returns the single parsed reply.
   ::
   :: Deliberately NOT `-e'. That flag reroutes a SERVER error reply (WRONGTYPE,
   :: ERR ...) to stderr and exits 1, which collides head-on with the stderr
   :: gate -- an ordinary WRONGTYPE would be raised as a connection failure.
   :: Without it, one-shot behaves exactly like piped mode: error replies print
   :: on stdout as error:\"...\" with exit 0, and stderr stays reserved for
   :: things that really did break the connection."
  (let* ((res  (my/redis--check (my/redis--run conn db args) conn))
         (line (car (split-string (plist-get res :out) "\n" t))))
    (if (null line)
        (if (zerop (plist-get res :exit)) :null (cons :raw ""))
      (my/redis--parse-line line))))

(defun my/redis--call-text (conn db &rest args)
  ":: One-shot call returning stdout as one string, `--json' suppressed.
   For the commands redis-cli hard-codes to raw output (INFO, CLIENT LIST,
   MEMORY DOCTOR, ...): they ignore --json and emit an unquoted multi-line
   payload, so there is nothing to parse and only the whole text is useful."
  (let ((res (my/redis--check (my/redis--run conn db args nil t) conn)))
    (plist-get res :out)))

(defun my/redis--call-stdin (conn db value &rest args)
  ":: One-shot call with VALUE as the last argument, fed over stdin via `-x'.
   Byte-exact: `-x' does not strip a trailing newline and does no re-quoting,
   so any value round-trips without touching the inline quoting rules."
  (let* ((res  (my/redis--check
                (my/redis--run conn db (cons "-x" args) value)
                conn))
         (line (car (split-string (plist-get res :out) "\n" t))))
    (if (null line) :null (my/redis--parse-line line))))

;; ──────────────────────────────────────────────────────
;; :: Display formatting
;; ──────────────────────────────────────────────────────

(defun my/redis--humanise-ttl (secs)
  ":: TTL seconds as a compact label. -1 is `no expiry', -2 is `key is gone'."
  (let ((n (my/redis--int secs)))
    (cond
     ((null n) "?")
     ((= n -1) "-")
     ((= n -2) "gone")
     ((< n 60) (format "%ds" n))
     ((< n 3600) (format "%dm %ds" (/ n 60) (% n 60)))
     ((< n 86400) (format "%dh %dm" (/ n 3600) (/ (% n 3600) 60)))
     (t (format "%dd %dh" (/ n 86400) (/ (% n 86400) 3600))))))

(defun my/redis--parse-duration (s)
  ":: \"30s\" / \"10m\" / \"2h\" / \"1d\" (or a bare number of seconds) -> seconds."
  (let ((s (string-trim (or s ""))))
    (cond
     ((string-empty-p s) nil)
     ((string-match "\\`\\([0-9]+\\)\\([smhd]\\)?\\'" s)
      (* (string-to-number (match-string 1 s))
         (pcase (match-string 2 s)
           ("m" 60) ("h" 3600) ("d" 86400) (_ 1))))
     (t (user-error "Bad duration %S -- use 30s / 10m / 2h / 1d" s)))))

(defun my/redis--escape-controls (s)
  ":: Make control characters visible so one cell stays one grid line."
  (replace-regexp-in-string
   "[\0-\010\013\014\016-\037\177]"
   (lambda (m) (format "\\\\x%02x" (aref m 0)))
   (replace-regexp-in-string
    "\n" "\\\\n"
    (replace-regexp-in-string
     "\r" "\\\\r"
     (replace-regexp-in-string "\t" "\\\\t" s)))))

(defun my/redis--cell-display (v)
  ":: One reply value as a single-line grid cell."
  (cond
   ((eq v :null) "(nil)")
   ((eq v :false) "false")
   ((eq v t) "true")
   ((null v) "")
   ((and (consp v) (eq (car v) :binary)) "(binary)")
   ((and (consp v) (eq (car v) :text))
    (my/redis--escape-controls (format "%s" (cdr v))))
   ((and (consp v) (eq (car v) :no-reply)) "(no reply)")
   ((and (consp v) (eq (car v) :error)) (format "(error) %s" (cdr v)))
   ((and (consp v) (memq (car v) '(:partial-error :raw)))
    (my/redis--escape-controls (format "%s" (cdr v))))
   ((numberp v) (number-to-string v))
   ((listp v) (format "[%d item%s]" (length v) (if (cdr v) "s" "")))
   (t (my/redis--escape-controls (format "%s" v)))))

(defun my/redis--format-reply (v &optional indent)
  ":: Pretty-print one reply the way interactive redis-cli would."
  (let ((pad (make-string (or indent 0) ?\s)))
    (cond
     ((eq v :null) (concat pad "(nil)"))
     ((eq v :false) (concat pad "(false)"))
     ((eq v t) (concat pad "(true)"))
     ((and (consp v) (eq (car v) :error)) (concat pad (format "(error) %s" (cdr v))))
     ((and (consp v) (eq (car v) :partial-error))
      (concat pad (format "(partial error) %s" (cdr v))))
     ((and (consp v) (eq (car v) :binary)) (concat pad "(binary value)"))
     ((and (consp v) (eq (car v) :no-reply)) (concat pad "(no reply)"))
     ((and (consp v) (eq (car v) :raw)) (concat pad (format "%s" (cdr v))))
     ((and (consp v) (eq (car v) :text)) (concat pad (format "%s" (cdr v))))
     ((integerp v) (concat pad (format "(integer) %d" v)))
     ((numberp v) (concat pad (format "%s" v)))
     ((null v) (concat pad "(empty array)"))
     ((listp v)
      (let ((i 0))
        (mapconcat (lambda (x)
                     (setq i (1+ i))
                     (let ((body (my/redis--format-reply x (+ (or indent 0) 3))))
                       (concat pad (format "%d) " i) (string-trim-left body))))
                   v "\n")))
     (t (concat pad (format "%S" v))))))

;; ──────────────────────────────────────────────────────
;; :: Scratch pad
;; ──────────────────────────────────────────────────────

(defvar my/redis-commands
  '("APPEND" "BITCOUNT" "COPY" "DBSIZE" "DECR" "DECRBY" "DEL" "EXISTS" "EXPIRE"
    "EXPIREAT" "FLUSHDB" "GET" "GETDEL" "GETEX" "GETRANGE" "GETSET" "HDEL"
    "HEXISTS" "HGET" "HGETALL" "HINCRBY" "HKEYS" "HLEN" "HMGET" "HRANDFIELD"
    "HSCAN" "HSET" "HSETNX" "HVALS" "INCR" "INCRBY" "INFO" "KEYS" "LINDEX"
    "LINSERT" "LLEN" "LMOVE" "LPOP" "LPUSH" "LRANGE" "LREM" "LSET" "LTRIM"
    "MEMORY" "MGET" "MSET" "OBJECT" "PERSIST" "PEXPIRE" "PING" "PTTL" "RANDOMKEY"
    "RENAME" "RENAMENX" "RPOP" "RPUSH" "SADD" "SCAN" "SCARD" "SDIFF" "SET"
    "SETEX" "SETNX" "SETRANGE" "SINTER" "SISMEMBER" "SMEMBERS" "SMOVE" "SPOP"
    "SRANDMEMBER" "SREM" "SSCAN" "STRLEN" "SUNION" "TTL" "TYPE" "UNLINK" "XADD"
    "XDEL" "XLEN" "XRANGE" "XREVRANGE" "ZADD" "ZCARD" "ZCOUNT" "ZINCRBY"
    "ZRANGE" "ZRANGEBYSCORE" "ZRANK" "ZREM" "ZREVRANGE" "ZSCAN" "ZSCORE")
  ":: Commands highlighted in the scratch pad and offered for completion.")

(defvar my/redis-cmd-mode-map (make-sparse-keymap))

(define-derived-mode my/redis-cmd-mode prog-mode "Redis-Cmd"
  ":: Editing mode for the Redis command scratch pad. One command per line, in
   redis-cli's own inline syntax (quote arguments containing spaces)."
  (setq-local comment-start "#")
  (setq-local comment-start-skip "#+[ \t]*")
  (setq-local font-lock-defaults
              (list (list (cons (concat "^[ \t]*\\_<"
                                        (regexp-opt my/redis-commands t)
                                        "\\_>")
                                '(1 font-lock-keyword-face))
                          (cons "^[ \t]*#.*$" 'font-lock-comment-face)))))

(defun my/redis-scratch ()
  ":: Open the reusable Redis command pad (SPC d R s)."
  (interactive)
  (let ((buf (get-buffer-create "*redis-scratch*")))
    (with-current-buffer buf
      (unless (derived-mode-p 'my/redis-cmd-mode) (my/redis-cmd-mode))
      (when (zerop (buffer-size))
        (insert "# Redis scratch.  , r run (region or line, C-u = whole buffer)\n"
                "#                 , c connection   , d db   , w save\n"
                "# One command per line, redis-cli inline syntax.\n"
                "# Blocking/streaming commands (SUBSCRIBE, MONITOR, BLPOP) and the\n"
                "# redis-cli prompt built-ins (exit, quit, help) are refused here --\n"
                "# use SPC d R c for a real REPL.\n\n")))
    (switch-to-buffer-other-window buf)))

(defun my/redis--scratch-conn ()
  ":: The pad's connection, prompting and remembering on first use."
  (or my/redis--conn
      (setq my/redis--conn (my/redis--read-conn "Run on connection: "))))

(defun my/redis-scratch-set-conn ()
  ":: Choose (or change) the connection the pad runs against."
  (interactive)
  (setq my/redis--conn (my/redis--read-conn "Run on connection: "))
  (setq my/redis--db (plist-get my/redis--conn :db))
  (message "Scratch connection: %s (db %s)"
           (plist-get my/redis--conn :name) my/redis--db))

(defun my/redis-scratch-set-db (n)
  ":: Choose the logical db the pad runs against."
  (interactive "nLogical db: ")
  (setq my/redis--db n)
  (message "Scratch db: %d" n))

(defun my/redis--scratch-lines (whole)
  ":: Lines to run: the region, the whole buffer with WHOLE, else the line
   at point."
  (split-string
   (cond (whole (buffer-substring-no-properties (point-min) (point-max)))
         ((use-region-p)
          (buffer-substring-no-properties (region-beginning) (region-end)))
         (t (buffer-substring-no-properties
             (line-beginning-position) (line-end-position))))
   "\n" t "[ \t\r]+"))

(defun my/redis-scratch-run (&optional whole)
  ":: Run the region (or the line at point; C-u for the whole buffer)."
  (interactive "P")
  (let* ((lines (my/redis--scratch-lines whole))
         (conn  (my/redis--scratch-conn))
         (db    (or my/redis--db (plist-get conn :db))))
    (when (null lines) (user-error "No commands to run"))
    (my/redis--open-replies conn db lines
                            (format "Redis scratch @ %s" (plist-get conn :name)))))

;; ──────────────────────────────────────────────────────
;; :: REPL -- a real redis-cli in a vterm side split
;; ──────────────────────────────────────────────────────

(defun my/redis-repl ()
  ":: Open an interactive redis-cli for a connection in a vterm (SPC d R c).
   The password is handed over via REDISCLI_AUTH in the spawned shell's
   environment, so it never reaches shell history. NOTE: it stays in that
   shell's environment for its lifetime -- anything you run in the same vterm
   inherits it."
  (interactive)
  (unless (fboundp 'vterm)
    (user-error "vterm not loaded -- enable ':term vterm' in init.el"))
  (let* ((conn (my/redis--read-conn "REPL on connection: "))
         (pass (my/redis--password conn))
         (user (plist-get conn :user))
         (cmd  (concat my/redis-repl-program
                       (format " -h %s -p %s -n %s"
                               (shell-quote-argument (plist-get conn :host))
                               (plist-get conn :port)
                               (plist-get conn :db))
                       (if (and pass user)
                           (format " --user %s" (shell-quote-argument user)) "")))
         (buf-name (generate-new-buffer-name
                    (format "*Redis REPL [%s]*" (plist-get conn :name))))
         (root (if (fboundp 'my/project-root) (my/project-root) default-directory)))
    (let ((process-environment (my/redis--environment conn pass)))
      (my/vterm-create buf-name root))
    (my/dev-register-buffer (get-buffer buf-name))
    (run-with-timer 0.4 nil
                    (lambda ()
                      (when-let ((b (get-buffer buf-name)))
                        (with-current-buffer b
                          (vterm-send-string (concat cmd "\n"))))))
    (my/focus-window (my/vterm-display buf-name))))

;; :: localleader for the scratch pad (mirrors db.el's sql-mode bindings)
(map! :map my/redis-cmd-mode-map
      :localleader
      :desc "Run (region/line)" "r" #'my/redis-scratch-run
      :desc "Set connection"    "c" #'my/redis-scratch-set-conn
      :desc "Set db"            "d" #'my/redis-scratch-set-db
      :desc "Save command"      "w" #'my/redis-save-command)

(provide 'my-redis)
