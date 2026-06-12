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
;; :: Package manager detection (lockfile-based)
;; ──────────────────────────────────────────────────────

(defun my/detect-package-manager (&optional root)
  ":: Detect frontend package manager from lockfile in ROOT."
  (let ((root (or root (my/project-root))))
    (cond
     ((file-exists-p (expand-file-name "pnpm-lock.yaml" root))   "pnpm")
     ((file-exists-p (expand-file-name "yarn.lock" root))        "yarn")
     ((file-exists-p (expand-file-name "package-lock.json" root)) "npm")
     (t "npm"))))

;; ──────────────────────────────────────────────────────
;; :: Django python resolver (venv > poetry > system)
;; ──────────────────────────────────────────────────────

(defun my/django-python (&optional root)
  ":: Return python executable or command prefix for Django in ROOT.
Prefers venv/bin/python, then poetry run python, then bare python."
  (let* ((root        (or root (my/project-root)))
         (venv-python (expand-file-name "venv/bin/python" root))
         (poetry-lock (expand-file-name "poetry.lock" root)))
    (cond
     ((file-exists-p venv-python) venv-python)
     ((file-exists-p poetry-lock) "poetry run python")
     (t "python"))))

;; ──────────────────────────────────────────────────────
;; :: Per-project overrides (.dev.el) + command resolution
;; ──────────────────────────────────────────────────────

(defvar my/dev-config-file ".dev.el"
  ":: Gitignored per-project file holding command overrides as an alist, e.g.
((frontend-dev   . \"pnpm dev\")
 (frontend-build . \"pnpm build\")
 (backend        . \"uv run python manage.py runserver\")).")

(defun my/project-config (&optional root)
  ":: Read per-project command overrides from `my/dev-config-file' at ROOT.
Returns an alist, or nil if the file is absent or unreadable."
  (let* ((root (or root (my/project-root)))
         (file (expand-file-name my/dev-config-file root)))
    (when (file-readable-p file)
      (ignore-errors
        (with-temp-buffer
          (insert-file-contents file)
          (car (read-from-string (buffer-string))))))))

(defun my/project-config-get (key &optional root)
  ":: Look up KEY in the project's overrides. Returns a command string or nil."
  (alist-get key (my/project-config root)))

(defun my/package-json-scripts (&optional root)
  ":: Return the scripts alist from package.json at ROOT, or nil.
Keys are symbols, values are the raw script strings."
  (let* ((root (or root (my/project-root)))
         (file (expand-file-name "package.json" root)))
    (when (file-readable-p file)
      (ignore-errors
        (with-temp-buffer
          (insert-file-contents file)
          (alist-get 'scripts (json-parse-string (buffer-string)
                                                 :object-type 'alist
                                                 :null-object nil)))))))

(defun my/frontend-dev-script (&optional root)
  ":: First of dev/start/develop that actually exists in package.json scripts."
  (let ((scripts (my/package-json-scripts root)))
    (seq-find (lambda (name) (assq (intern name) scripts))
              '("dev" "start" "develop"))))

(defun my/frontend-dev-command (&optional root)
  ":: Resolve frontend dev cmd: override > package.json script > lockfile default."
  (let* ((root (or root (my/project-root)))
         (pm   (my/detect-package-manager root)))
    (or (my/project-config-get 'frontend-dev root)
        (when-let ((script (my/frontend-dev-script root)))
          (format "%s run %s" pm script))
        (format "%s run dev" pm))))

(defun my/frontend-build-command (&optional root)
  ":: Resolve frontend build cmd: override > lockfile default."
  (let* ((root (or root (my/project-root)))
         (pm   (my/detect-package-manager root)))
    (or (my/project-config-get 'frontend-build root)
        (format "%s run build" pm))))

(defun my/backend-command (&optional root)
  ":: Resolve backend server cmd: override > Django default."
  (let* ((root   (or root (my/project-root)))
         (python (my/django-python root)))
    (or (my/project-config-get 'backend root)
        (format "%s manage.py runserver" python))))

(defun my/dev-config-template (&optional root)
  ":: Return a commented `.dev.el' scaffold showing ROOT's resolved defaults."
  (let ((root (or root (my/project-root))))
    (format
     (concat
      ";; :: %s -- per-project dev command overrides (gitignored)\n"
      ";; :: Only the keys you set here win; everything else uses detection.\n"
      ";;\n"
      ";; :: Current resolved defaults for this project:\n"
      ";; ::   frontend-dev   => %S\n"
      ";; ::   frontend-build => %S\n"
      ";; ::   backend        => %S\n"
      ";;\n"
      ";; :: Uncomment and edit any line to override.\n"
      "(\n"
      " ;; (frontend-dev   . \"turbo dev --filter=web\")\n"
      " ;; (frontend-build . \"pnpm build\")\n"
      " ;; (backend        . \"uv run python manage.py runserver\")\n"
      ")\n")
     my/dev-config-file
     (my/frontend-dev-command root)
     (my/frontend-build-command root)
     (my/backend-command root))))

(defun my/dev-config-edit ()
  ":: Open the project's `.dev.el', scaffolding a commented template if absent."
  (interactive)
  (let* ((root (my/project-root))
         (file (expand-file-name my/dev-config-file root))
         (new  (not (file-exists-p file))))
    (find-file file)
    (when (and new (zerop (buffer-size)))
      (insert (my/dev-config-template root))
      (goto-char (point-min)))))

;; ──────────────────────────────────────────────────────
;; :: Process registry  -- keyed by (root . type)
;; ──────────────────────────────────────────────────────

(defvar my/dev-processes (make-hash-table :test 'equal)
  ":: Running dev processes, keyed by (project-root . server-type).")

(defun my/dev-proc-get (root type)
  (gethash (cons root type) my/dev-processes))

(defun my/dev-proc-set (root type proc)
  (puthash (cons root type) proc my/dev-processes))

(defun my/dev-proc-live-p (root type)
  (let ((p (my/dev-proc-get root type)))
    (and p (process-live-p p))))

(defun my/dev-proc-kill (root type)
  (let ((p (my/dev-proc-get root type)))
    (when (and p (process-live-p p)) (kill-process p)))
  (remhash (cons root type) my/dev-processes))

;; ──────────────────────────────────────────────────────
;; :: Buffer and display helpers
;; ──────────────────────────────────────────────────────

(defun my/dev-buffer-name (type &optional root)
  ":: Return log buffer name for TYPE in project ROOT."
  (format "*%s [%s]*" type (if root
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

(defun my/dev-log-slot (type)
  ":: Bottom-side slot for a dev-log TYPE, so logs sit side by side."
  (pcase type
    ("Frontend" 0)
    ("Django"   1)
    (_          0)))

(defun my/display-dev-log (buf type)
  ":: Display a dev-server log BUF across the bottom, slotted by TYPE."
  (my/display-in-side buf 'bottom (my/dev-log-slot type) 0.30))

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
;; :: Generic server lifecycle
;; ──────────────────────────────────────────────────────

(defun my/dev-start-server (type cmd)
  ":: Start a named server TYPE by running CMD at the project root.
Creates a log buffer and opens it in a side split."
  (let* ((root  (my/project-root))
         (bname (my/dev-buffer-name type root))
         (buf   (my/prepare-log-buffer bname))
         (proc  (start-process-shell-command
                 type buf
                 (format "cd %s && %s" (shell-quote-argument root) cmd))))
    (set-process-filter proc #'my/dev-process-filter)
    (set-process-sentinel
     proc (lambda (p _)
            (message "[web.el] %s %s." type (process-status p))))
    (my/dev-proc-set root type proc)
    (my/display-dev-log buf type)
    (message "%s started (detected: %s)." type cmd)))

(defun my/dev-stop-server (type)
  ":: Kill the running server of TYPE for the current project."
  (let ((root (my/project-root)))
    (if (my/dev-proc-live-p root type)
        (progn
          (my/dev-proc-kill root type)
          (message "%s stopped." type))
      (message "No %s running for [%s]." type (my/project-name)))))

(defun my/dev-open-logs (type)
  ":: Show the log buffer for TYPE in a side split."
  (let* ((root (my/project-root))
         (buf  (get-buffer (my/dev-buffer-name type root))))
    (if buf
        (my/display-dev-log buf type)
      (message "No %s log buffer yet -- start the server first." type))))

(defun my/dev-clear-logs (type)
  ":: Clear the log buffer for TYPE."
  (let* ((root (my/project-root))
         (buf  (get-buffer (my/dev-buffer-name type root))))
    (if buf
        (progn
          (with-current-buffer buf
            (let ((inhibit-read-only t)) (erase-buffer)))
          (message "%s logs cleared." type))
      (message "No %s log buffer to clear." type))))

;; ──────────────────────────────────────────────────────
;; :: Frontend commands
;; ──────────────────────────────────────────────────────

(defun my/frontend-start ()
  ":: Start the frontend dev server (override > package.json script > default)."
  (interactive)
  (let ((root (my/project-root)))
    (if (my/dev-proc-live-p root "Frontend")
        (message "Frontend already running for [%s]." (my/project-name))
      (my/dev-start-server "Frontend" (my/frontend-dev-command root)))))

(defun my/frontend-stop ()
  ":: Stop the frontend dev server."
  (interactive)
  (my/dev-stop-server "Frontend"))

(defun my/frontend-build ()
  ":: Run the frontend build in a compilation buffer (override > default)."
  (interactive)
  (let ((root (my/project-root)))
    (compile (format "cd %s && %s"
                     (shell-quote-argument root)
                     (my/frontend-build-command root)))))

(defun my/frontend-logs ()
  ":: Show frontend log buffer in a side split."
  (interactive)
  (my/dev-open-logs "Frontend"))

(defun my/frontend-logs-clear ()
  ":: Clear the frontend log buffer."
  (interactive)
  (my/dev-clear-logs "Frontend"))

;; ──────────────────────────────────────────────────────
;; :: Backend / Django commands
;; ──────────────────────────────────────────────────────

(defun my/backend-start ()
  ":: Start the backend server (override > venv/poetry/system Django default)."
  (interactive)
  (let ((root (my/project-root)))
    (if (my/dev-proc-live-p root "Django")
        (message "Django already running for [%s]." (my/project-name))
      (my/dev-start-server "Django" (my/backend-command root)))))

(defun my/backend-stop ()
  ":: Stop Django runserver."
  (interactive)
  (my/dev-stop-server "Django"))

(defun my/backend-logs ()
  ":: Show Django log buffer in a side split."
  (interactive)
  (my/dev-open-logs "Django"))

(defun my/backend-logs-clear ()
  ":: Clear the Django log buffer."
  (interactive)
  (my/dev-clear-logs "Django"))

(defun my/backend-manage ()
  ":: Run an arbitrary Django management command interactively."
  (interactive)
  (let* ((root   (my/project-root))
         (python (my/django-python root))
         (cmd    (read-string "manage.py command: " "migrate")))
    (compile (format "cd %s && %s manage.py %s"
                     (shell-quote-argument root) python cmd))))

;; ──────────────────────────────────────────────────────
;; :: Status
;; ──────────────────────────────────────────────────────

(defun my/dev-status ()
  ":: Show running server status for the current project."
  (interactive)
  (let* ((root (my/project-root))
         (fe   (if (my/dev-proc-live-p root "Frontend") "running" "stopped"))
         (be   (if (my/dev-proc-live-p root "Django")   "running" "stopped")))
    (message "[%s]  Frontend: %s  |  Django: %s"
             (my/project-name) fe be)))

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
