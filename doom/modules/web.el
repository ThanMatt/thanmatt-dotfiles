;;; modules/web.el -*- lexical-binding: t; -*-

;; ──────────────────────────────────────────────────────
;; :: Helpers
;; ──────────────────────────────────────────────────────

(defun my/project-root ()
  ":: Return current project root, falling back to default-directory."
  (or (and (fboundp 'projectile-project-root)
           (ignore-errors (projectile-project-root)))
      default-directory))

(defun my/project-name ()
  ":: Short name of the current project for buffer labels."
  (file-name-nondirectory (directory-file-name (my/project-root))))

;; ──────────────────────────────────────────────────────
;; :: Per-project command config (.dev.el)
;; ──────────────────────────────────────────────────────

(defvar my/dev-config-file ".dev.el"
  ":: Gitignored per-project file listing dev commands as plists, e.g.
((:name \"Frontend Dev\" :cmd \"pnpm dev\"     :type server)
 (:name \"Build\"        :cmd \"pnpm build\"    :type compile)
 (:name \"Shell\"        :cmd \"manage.py shell\" :type vterm)).")

(defun my/project-config (&optional root)
  ":: Read the raw command list from `my/dev-config-file' at ROOT.
Returns a list of plists, or nil if the file is absent or unreadable."
  (let* ((root (or root (my/project-root)))
         (file (expand-file-name my/dev-config-file root)))
    (when (file-readable-p file)
      (ignore-errors
        (with-temp-buffer
          (insert-file-contents file)
          (car (read-from-string (buffer-string))))))))

(defun my/project-commands (&optional root)
  ":: Normalized commands from `.dev.el': plists with :name, :cmd, :type.
Entries missing :name or :cmd are dropped; :type defaults to `server'."
  (seq-keep
   (lambda (c)
     (let ((name (plist-get c :name))
           (cmd  (plist-get c :cmd))
           (type (or (plist-get c :type) 'server)))
       (when (and (stringp name) (stringp cmd))
         (list :name name :cmd cmd :type type))))
   (my/project-config root)))

(defun my/dev-config-template ()
  ":: Return a `.dev.el' scaffold documenting the plist schema."
  (concat
   ";; :: " my/dev-config-file " -- per-project dev commands (gitignored)\n"
   ";; :: Each entry is a plist:\n"
   ";; ::   :name  label shown in the picker    (required)\n"
   ";; ::   :cmd   shell command, run at root    (required)\n"
   ";; ::   :type  server | compile | vterm      (optional, default server)\n"
   ";; ::\n"
   ";; :: server  = long-running, logged, stoppable   (dev servers)\n"
   ";; :: compile = one-shot in a compilation buffer   (builds, migrations)\n"
   ";; :: vterm   = interactive terminal               (REPLs, shells)\n"
   "(\n"
   " (:name \"Frontend Dev\"   :cmd \"pnpm dev\"                  :type server)\n"
   " (:name \"Frontend Build\" :cmd \"pnpm build\"                :type compile)\n"
   " (:name \"Backend\"        :cmd \"python manage.py runserver\" :type server)\n"
   " (:name \"Migrate\"        :cmd \"python manage.py migrate\"   :type compile)\n"
   " (:name \"Django Shell\"   :cmd \"python manage.py shell\"     :type vterm)\n"
   ")\n"))

(defun my/dev-config-edit ()
  ":: Open the project's `.dev.el', scaffolding a template if absent."
  (interactive)
  (let* ((root (my/project-root))
         (file (expand-file-name my/dev-config-file root))
         (new  (not (file-exists-p file))))
    (find-file file)
    (when (and new (zerop (buffer-size)))
      (insert (my/dev-config-template))
      (goto-char (point-min)))))

;; ──────────────────────────────────────────────────────
;; :: Process registry  -- keyed by (root . name)
;; ──────────────────────────────────────────────────────

(defvar my/dev-processes (make-hash-table :test 'equal)
  ":: Running dev processes, keyed by (project-root . command-name).")

(defun my/dev-proc-get (root name)
  (gethash (cons root name) my/dev-processes))

(defun my/dev-proc-set (root name proc)
  (puthash (cons root name) proc my/dev-processes))

(defun my/dev-proc-live-p (root name)
  (let ((p (my/dev-proc-get root name)))
    (and p (process-live-p p))))

(defun my/dev-proc-kill (root name)
  (let ((p (my/dev-proc-get root name)))
    (when (and p (process-live-p p)) (kill-process p)))
  (remhash (cons root name) my/dev-processes))

(defun my/dev-server-names (&optional root)
  ":: Command names registered for ROOT (running or exited), in insertion order."
  (let ((root (or root (my/project-root)))
        names)
    (maphash (lambda (k _) (when (equal (car k) root) (push (cdr k) names)))
             my/dev-processes)
    (nreverse names)))

;; ──────────────────────────────────────────────────────
;; :: Buffer and display helpers
;; ──────────────────────────────────────────────────────

(defun my/dev-buffer-name (name &optional root)
  ":: Return log buffer name for command NAME in project ROOT."
  (format "*%s [%s]*" name (if root
                               (file-name-nondirectory (directory-file-name root))
                             (my/project-name))))

(defun my/display-in-side (buf side slot size)
  ":: Display BUF in a SIDE window at SLOT.
SIZE is a frame fraction: window-width for left/right, window-height for
top/bottom. Distinct slots on the same side coexist instead of replacing."
  (display-buffer
   buf
   `(display-buffer-in-side-window
     (side . ,side)
     (slot . ,slot)
     (,(if (memq side '(left right)) 'window-width 'window-height) . ,size))))

(defun my/display-side-split (buf)
  ":: Display BUF in the persistent right side window (interactive terminals)."
  (my/display-in-side buf 'right 0 0.40))

(defun my/focus-window (window)
  ":: Select WINDOW and, for vterm buffers, drop into insert state.
WINDOW is whatever `display-buffer' returned; no-op if it isn't live."
  (when (window-live-p window)
    (select-window window)
    (when (and (eq major-mode 'vterm-mode) (fboundp 'evil-insert-state))
      (evil-insert-state))))

(defvar my/dev-log-slots (make-hash-table :test 'equal)
  ":: Stable bottom-side slot per command name, so logs sit side by side.")

(defun my/dev-log-slot (name)
  ":: Return a stable bottom-side slot for NAME, assigning one on first use."
  (or (gethash name my/dev-log-slots)
      (puthash name (hash-table-count my/dev-log-slots) my/dev-log-slots)))

(defun my/dev-register-buffer (buf)
  ":: Make BUF discoverable in `SPC ,' and `SPC b b'.
Dev buffers are created bypassing Doom's popup system, so persp-mode never
adds them to the current workspace and the workspace switchers hide them.
Add BUF to the current perspective explicitly, and mark it real."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (setq-local doom-real-buffer-p t))   ; :: survive workspace buffer filters
    (when-let* (((bound-and-true-p persp-mode))
                ((fboundp 'persp-add-buffer))
                (persp (and (fboundp 'get-current-persp) (get-current-persp))))
      ;; :: nil `switch' arg -> add without stealing focus to BUF
      (persp-add-buffer buf persp nil))))

(defun my/display-dev-log (buf)
  ":: Re-surface a dev log/compile BUF.
Compile buffers pop back through their Doom popup rule (and take focus, since
you asked for them); server logs get a persistent bottom side window."
  (my/dev-register-buffer buf)
  (if (string-prefix-p "*compile: " (buffer-name buf))
      (pop-to-buffer buf)
    (my/display-in-side buf 'bottom (my/dev-log-slot (buffer-name buf)) 0.30)))

(defun my/prepare-log-buffer (name)
  ":: Create or clear NAME as a read-only log buffer. Returns buffer."
  (require 'ansi-color)
  (let ((buf (get-buffer-create name)))
    (with-current-buffer buf
      (special-mode)                       ; :: read-only; q closes the window
      (setq-local ansi-color-context nil)  ; :: reset SGR state for ANSI decode
      (let ((inhibit-read-only t)) (erase-buffer)))
    buf))

(defun my/dev-process-filter (proc string)
  ":: Append STRING from PROC into its buffer and auto-scroll."
  (when (buffer-live-p (process-buffer proc))
    (with-current-buffer (process-buffer proc)
      (let ((inhibit-read-only t)
            (at-end (= (point) (point-max))))
        (goto-char (point-max))
        ;; :: decode ANSI colors and strip cursor-control sequences; the
        ;; :: buffer-local `ansi-color-context' carries SGR state across chunks
        (insert (ansi-color-apply string))
        (when at-end (goto-char (point-max)))))))

;; ──────────────────────────────────────────────────────
;; :: Server lifecycle (long-running, logged, stoppable)
;; ──────────────────────────────────────────────────────

(defun my/dev-start-server (name cmd)
  ":: Start (or resurface) a long-running server NAME running CMD at root.
If one is already live, just surfaces its log buffer instead of duplicating."
  (let ((root (my/project-root)))
    (if (my/dev-proc-live-p root name)
        (progn
          (message "%s already running for [%s]." name (my/project-name))
          (my/dev-open-logs name))
      (let* ((bname (my/dev-buffer-name name root))
             (buf   (my/prepare-log-buffer bname))
             (proc  (start-process-shell-command
                     name buf
                     (format "cd %s && %s" (shell-quote-argument root) cmd))))
        (set-process-filter proc #'my/dev-process-filter)
        (set-process-sentinel
         proc (lambda (p _)
                (message "[web.el] %s %s." name (process-status p))))
        (my/dev-proc-set root name proc)
        (my/display-dev-log buf)
        (message "%s started: %s" name cmd)))))

(defun my/dev-stop-server (name)
  ":: Kill the running server NAME for the current project."
  (let ((root (my/project-root)))
    (if (my/dev-proc-live-p root name)
        (progn
          (my/dev-proc-kill root name)
          (message "%s stopped." name))
      (message "No %s running for [%s]." name (my/project-name)))))

(defun my/dev-open-logs (name)
  ":: Show the log buffer for command NAME in a side split."
  (let* ((root (my/project-root))
         (buf  (get-buffer (my/dev-buffer-name name root))))
    (if buf
        (my/display-dev-log buf)
      (message "No %s log buffer yet -- run it first." name))))

(defun my/dev-clear-logs (name)
  ":: Clear the log buffer for command NAME."
  (let* ((root (my/project-root))
         (buf  (get-buffer (my/dev-buffer-name name root))))
    (if buf
        (progn
          (with-current-buffer buf
            (let ((inhibit-read-only t)) (erase-buffer)))
          (message "%s logs cleared." name))
      (message "No %s log buffer to clear." name))))

;; ──────────────────────────────────────────────────────
;; :: Compile buffers as Doom popups
;; ──────────────────────────────────────────────────────

(when (fboundp 'set-popup-rule!)
  ;; :: `:ttl nil'  -> never auto-kill; closing keeps the build log around
  ;; ::                (still findable via SPC , / SPC b b / SPC d l).
  ;; :: `:select nil' -> a running build doesn't steal focus from your code;
  ;; ::                deliberate re-opens use `pop-to-buffer' and DO focus it.
  ;; :: `:quit t'   -> q / ESC / C-g dismisses the popup (buffer survives).
  (set-popup-rule! "^\\*compile: "
    :side 'bottom :size 0.30 :select nil :quit t :ttl nil :modeline t))

(defadvice! my/dev-compile-obeys-popup-a (fn buffer-or-name &rest args)
  ":: Route `switch-to-buffer' to `pop-to-buffer' for compile popups.
`switch-to-buffer' ignores `display-buffer-alist', so reaching a compile
buffer via SPC , / SPC b b would hijack the current window. Rerouting to
`pop-to-buffer' makes it honor the popup rule and land in the bottom slot."
  :around #'switch-to-buffer
  (let ((buf (ignore-errors (get-buffer buffer-or-name))))
    (if (and (bufferp buf)
             (string-prefix-p "*compile: " (buffer-name buf)))
        (pop-to-buffer buf)
      (apply fn buffer-or-name args))))

;; ──────────────────────────────────────────────────────
;; :: Command runners  -- dispatched by :type
;; ──────────────────────────────────────────────────────

(defun my/dev-run-compile (name cmd root)
  ":: Run CMD one-shot in its own compilation buffer, shown as a Doom popup.
The buffer is named per NAME so re-runs don't clobber other commands' output;
its popup rule (`^\\*compile: ', `:ttl nil') means `q' only buries it -- the
process keeps running and the buffer stays findable in SPC , / SPC d l."
  (let* ((bufname (format "*compile: %s [%s]*" name (my/project-name)))
         (default-directory root)
         (compilation-buffer-name-function (lambda (_mode) bufname)))
    ;; :: `compile' displays via `display-buffer' -> hits the popup rule above
    ;; :: (no focus steal). It returns the buffer; register it for SPC , / SPC b b.
    (let ((buf (compile (format "cd %s && %s" (shell-quote-argument root) cmd))))
      (when (buffer-live-p buf)
        (my/dev-register-buffer buf))
      buf)))

(defun my/dev-run-vterm (name cmd root)
  ":: Run CMD in an interactive vterm side split, reusing one buffer per NAME."
  (unless (fboundp 'vterm)
    (user-error "vterm not loaded -- enable ':term vterm' in init.el"))
  (let* ((bufname (my/dev-buffer-name name root))
         (buf     (get-buffer bufname)))
    (if (buffer-live-p buf)
        (my/focus-window (my/vterm-display buf))
      (my/vterm-create bufname root)
      (run-with-timer 0.4 nil
                      (lambda ()
                        (when-let ((b (get-buffer bufname)))
                          (with-current-buffer b
                            (vterm-send-string (concat cmd "\n"))))))
      (my/focus-window (my/vterm-display bufname)))))

(defun my/dev-run-command (spec)
  ":: Run a normalized command SPEC (plist of :name :cmd :type) at project root."
  (let ((name (plist-get spec :name))
        (cmd  (plist-get spec :cmd))
        (type (plist-get spec :type))
        (root (my/project-root)))
    (pcase type
      ('server  (my/dev-start-server name cmd))
      ('compile (my/dev-run-compile name cmd root))
      ('vterm   (my/dev-run-vterm name cmd root))
      (_        (user-error "Unknown :type %S for command %s" type name)))))

;; ──────────────────────────────────────────────────────
;; :: Entry points
;; ──────────────────────────────────────────────────────

(defun my/project-run ()
  ":: Pick a command from `.dev.el' and run it according to its :type."
  (interactive)
  (let* ((root (my/project-root))
         (cmds (my/project-commands root)))
    (if (null cmds)
        (when (y-or-n-p
               (format "No commands in %s for [%s]. Create it? "
                       my/dev-config-file (my/project-name)))
          (my/dev-config-edit))
      (let* ((names  (mapcar (lambda (c) (plist-get c :name)) cmds))
             (choice (completing-read (format "Run in [%s]: " (my/project-name))
                                      names nil t))
             (spec   (seq-find (lambda (c) (equal (plist-get c :name) choice))
                               cmds)))
        (when spec (my/dev-run-command spec))))))

(defun my/project-stop ()
  ":: Pick a running server for this project and stop it."
  (interactive)
  (let* ((root (my/project-root))
         (live (seq-filter (lambda (n) (my/dev-proc-live-p root n))
                           (my/dev-server-names root))))
    (pcase live
      ('()       (message "No running servers for [%s]." (my/project-name)))
      (`(,only)  (my/dev-stop-server only))
      (_         (my/dev-stop-server
                  (completing-read "Stop server: " live nil t))))))

(defun my/dev-log-buffers (&optional root)
  ":: This project's viewable log buffers: server logs + compile buffers.
Compile buffers are matched by name (`*compile: NAME [proj]*'), so a build
you closed with `q' is still listed here as long as its buffer is alive."
  (let* ((root    (or root (my/project-root)))
         (proj    (file-name-nondirectory (directory-file-name root)))
         (suffix  (format "[%s]*" proj))
         (server  (seq-keep (lambda (n) (get-buffer (my/dev-buffer-name n root)))
                            (my/dev-server-names root)))
         (compile (seq-filter
                   (lambda (b)
                     (let ((n (buffer-name b)))
                       (and (string-prefix-p "*compile: " n)
                            (string-suffix-p suffix n))))
                   (buffer-list))))
    (delete-dups (append server compile))))

(defun my/project-logs ()
  ":: Pick a server log or compile buffer for this project and re-surface it.
Includes buffers you closed with `q' -- that only removed the window; the
process keeps running and this brings the buffer back in a bottom split."
  (interactive)
  (let ((bufs (my/dev-log-buffers)))
    (pcase bufs
      ('()       (message "No dev logs for [%s]." (my/project-name)))
      (`(,only)  (my/display-dev-log only))
      (_         (let ((choice (completing-read
                                "Show log: " (mapcar #'buffer-name bufs) nil t)))
                   (when-let ((b (get-buffer choice)))
                     (my/display-dev-log b)))))))

(defun my/project-logs-clear ()
  ":: Pick a server for this project and clear its log buffer."
  (interactive)
  (let ((names (my/dev-server-names)))
    (pcase names
      ('()       (message "No server logs for [%s]." (my/project-name)))
      (`(,only)  (my/dev-clear-logs only))
      (_         (my/dev-clear-logs
                  (completing-read "Clear logs: " names nil t))))))

;; ──────────────────────────────────────────────────────
;; :: Status
;; ──────────────────────────────────────────────────────

(defun my/dev-status ()
  ":: Show running/stopped status of this project's servers."
  (interactive)
  (let* ((root  (my/project-root))
         (names (my/dev-server-names root)))
    (if (null names)
        (message "[%s] no servers started." (my/project-name))
      (message "[%s]  %s"
               (my/project-name)
               (mapconcat
                (lambda (n)
                  (format "%s: %s" n
                          (if (my/dev-proc-live-p root n) "running" "stopped")))
                names "  |  ")))))

;; ──────────────────────────────────────────────────────
;; :: Claude Code
;; ──────────────────────────────────────────────────────

(defun my/claude-code ()
  ":: Open Claude Code in a vterm side split at the current project root.
Re-uses the buffer if it already exists."
  (interactive)
  (unless (fboundp 'vterm)
    (user-error "vterm not loaded -- enable ':term vterm' in init.el"))
  (let* ((root     (my/project-root))
         (buf-name (format "*Claude Code [%s]*" (my/project-name))))
    (if (buffer-live-p (get-buffer buf-name))
        ;; :: already open, just surface it and focus
        (my/focus-window (my/display-side-split (get-buffer buf-name)))
      ;; :: create fresh vterm without hijacking window layout
      (let ((default-directory root))
        (save-window-excursion (vterm buf-name)))
      ;; :: small delay for vterm to initialize before sending the command
      (run-with-timer 0.4 nil
                      (lambda ()
                        (when-let ((buf (get-buffer buf-name)))
                          (with-current-buffer buf
                            (vterm-send-string "claude\n")))))
      ;; :: show the buffer and move point into it so typing goes to Claude
      (my/focus-window (my/display-side-split (get-buffer-create buf-name))))))

;; ──────────────────────────────────────────────────────
;; :: ncspot (Spotify TUI)
;; ──────────────────────────────────────────────────────

(defun my/ncspot ()
  ":: Toggle ncspot in a persistent vterm side split (global, not per-project).
First call spawns ncspot; later calls show/hide the same session so playback
keeps running while the window is hidden."
  (interactive)
  (unless (fboundp 'vterm)
    (user-error "vterm not loaded -- enable ':term vterm' in init.el"))
  (let* ((buf-name "*ncspot*")
         (buf      (get-buffer buf-name))
         (win      (and buf (get-buffer-window buf))))
    (cond
     ;; :: visible -> hide the window; ncspot keeps playing in the background
     (win (if (one-window-p)
              (bury-buffer buf)
            (let ((ignore-window-parameters t)) (delete-window win))))
     ;; :: exists but hidden -> surface and focus it
     (buf (my/focus-window (my/vterm-display buf)))
     ;; :: doesn't exist -> create from $HOME, launch ncspot, then show + focus
     (t
      (let ((default-directory (expand-file-name "~/"))
            display-buffer-alist)          ; :: bypass popup :ttl 0 so hide ≠ kill
        (save-window-excursion (vterm buf-name)))
      (run-with-timer 0.4 nil
                      (lambda ()
                        (when-let ((b (get-buffer buf-name)))
                          (with-current-buffer b
                            (vterm-send-string "ncspot\n")))))
      (my/focus-window (my/vterm-display buf-name))))))

;; ──────────────────────────────────────────────────────
;; :: Project vterm (general scratch terminal)
;; ──────────────────────────────────────────────────────

(defun my/vterm-resync-size (window)
  ":: Force the vterm PTY to match WINDOW's actual dimensions.
vterm sizes the PTY to whichever window is selected when the process is
*created* (see `vterm.el' make-process). Because we create vterms inside a
`save-window-excursion' (wrong-sized window) and then display them in a
narrow side window, the shell keeps the stale, too-wide column count — so
fish wraps/redraws at the wrong column (the \"seizure\" + garbled redraw
that a manual resize fixes). Re-running vterm's own resize hook against the
final window syncs `$COLUMNS'/`$LINES' to what's on screen."
  (when (window-live-p window)
    (let ((proc (get-buffer-process (window-buffer window))))
      (when (and (fboundp 'vterm--window-adjust-process-window-size)
                 (process-live-p proc))
        (with-selected-window window
          (vterm--window-adjust-process-window-size proc (list window)))))))

(defun my/vterm-display (buffer-or-name)
  ":: Show a vterm in a right-side window, BYPASSING Doom's popup system.
Binding `display-buffer-alist' to nil is the key: it stops the `^*vterm'
popup rule (and its :ttl 0) from attaching to the window, so hiding the
vterm with `delete-window' never kills the buffer/process — exactly why
the Claude Code buffer persists. Returns the displayed window."
  (let* (display-buffer-alist
         (window
          (display-buffer
           (get-buffer buffer-or-name)
           '((display-buffer-reuse-window display-buffer-in-side-window)
             (side . right) (slot . 1) (window-width . 0.40)))))
    (my/vterm-resync-size window)
    window))

(defun my/vterm-create (buf-name root)
  ":: Create vterm BUF-NAME at ROOT without the popup system hijacking it."
  (let ((default-directory root)
        display-buffer-alist)            ; :: keep creation out of popups too
    (save-window-excursion (vterm buf-name))))

(defun my/project-vterm ()
  ":: Toggle the project's primary vterm (show / hide; never kills it).
Reuses a single buffer per project — use `my/project-vterm-new' (SPC d T)
for extra terminals.

NOTE: `vterm' with a string arg always `generate-new-buffer's, so we look
the buffer up by name ourselves to avoid spawning duplicates."
  (interactive)
  (unless (fboundp 'vterm)
    (user-error "vterm not loaded -- enable ':term vterm' in init.el"))
  (let* ((root     (my/project-root))
         (buf-name (format "*vterm [%s]*" (my/project-name)))
         (buf      (get-buffer buf-name))
         (win      (and buf (get-buffer-window buf))))
    (cond
     ;; :: visible -> hide it (window only; the shell keeps running)
     (win (if (one-window-p)
              (bury-buffer buf)
            (let ((ignore-window-parameters t)) (delete-window win))))
     ;; :: exists but hidden -> show + focus
     (buf (my/focus-window (my/vterm-display buf)))
     ;; :: doesn't exist -> create at project root, then show + focus
     (t
      (my/vterm-create buf-name root)
      (my/focus-window (my/vterm-display buf-name))))))

(defun my/project-vterm-new ()
  ":: Spawn a fresh, uniquely-named vterm at the project root.
Unlike `my/project-vterm' (which reuses one buffer), each call creates a
new session — *vterm [proj]*, *vterm [proj]*<2>, etc."
  (interactive)
  (unless (fboundp 'vterm)
    (user-error "vterm not loaded -- enable ':term vterm' in init.el"))
  (let* ((root     (my/project-root))
         (buf-name (generate-new-buffer-name
                    (format "*vterm [%s]*" (my/project-name)))))
    (my/vterm-create buf-name root)
    (my/focus-window (my/vterm-display buf-name))))

(defun my/vterm-buffers ()
  ":: Live vterm-mode buffers scoped to the current Doom workspace.
Falls back to all buffers when workspaces (persp-mode) aren't active."
  (cl-remove-if-not
   (lambda (buf) (eq (buffer-local-value 'major-mode buf) 'vterm-mode))
   (if (fboundp '+workspace-buffer-list)
       (+workspace-buffer-list)
     (buffer-list))))

(defun my/vterm-switch ()
  ":: Pick a live vterm in the current workspace, with live preview.
Since the vterms share a name, moving through candidates temporarily shows
the highlighted one (via consult's `:state'); the original layout is
restored on exit, then the final pick is displayed and focused. Falls back
to plain `completing-read' if consult isn't available."
  (interactive)
  (let ((bufs (my/vterm-buffers)))
    (if (null bufs)
        (when (y-or-n-p "No vterm in this workspace. Create the project vterm? ")
          (my/project-vterm))
      (let* ((names  (mapcar #'buffer-name bufs))
             (wconf  (current-window-configuration))
             (choice
              (if (require 'consult nil t)
                  (unwind-protect
                      (consult--read
                       names
                       :prompt        "Switch to vterm: "
                       :category      'buffer
                       :require-match t
                       :sort          nil
                       :state
                       (lambda (action cand)
                         ;; :: preview the highlighted vterm; restore happens
                         ;; :: below regardless of selection or C-g abort
                         (when (and (eq action 'preview) cand (get-buffer cand))
                           (my/vterm-display cand))))
                    (set-window-configuration wconf))
                (completing-read "Switch to vterm: " names nil t))))
        (when (and choice (get-buffer choice))
          (my/focus-window (my/vterm-display choice)))))))

(defun my/vterm-kill ()
  ":: Pick a live vterm in the current workspace and kill it (close it).
Skips the \"buffer has a running process\" prompt — the pick is explicit."
  (interactive)
  (let ((bufs (my/vterm-buffers)))
    (if (null bufs)
        (message "No vterm buffers to kill.")
      (let* ((names  (mapcar #'buffer-name bufs))
             (choice (completing-read "Kill vterm: " names nil t)))
        (when (and choice (get-buffer choice))
          (let ((kill-buffer-query-functions nil))
            (kill-buffer choice))
          (message "Killed %s" choice))))))

;; ──────────────────────────────────────────────────────
;; :: Workspace shortcuts
;; ──────────────────────────────────────────────────────

(defun my/workspace-switch (name)
  ":: Switch to named workspace, creating it if it doesn't exist."
  (if (fboundp '+workspace-switch)
      (+workspace-switch name t)
    (message "Enable ':ui workspaces' in init.el for workspace support.")))

(defun my/workspace-frontend ()
  ":: Switch to the frontend workspace."
  (interactive) (my/workspace-switch "frontend"))

(defun my/workspace-backend ()
  ":: Switch to the backend workspace."
  (interactive) (my/workspace-switch "backend"))
