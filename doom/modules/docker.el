;;; modules/docker.el -*- lexical-binding: t; -*-

;; :: Docker from inside Emacs -- container listing, shells, logs.
;; ::
;; ::   SPC d D p    docker ps          (C-u -> -a, include stopped)
;; ::   SPC d D d    dps                (the short fish alias from fish/config.fish)
;; ::   SPC d D e    docker exec -it    (pick container, then a shell or any command)
;; ::   SPC d D l    docker logs -f     (pick container)
;; ::
;; :: In the *Docker ps* buffer, acting on the container under point:
;; ::   RET / e   exec into it     l   follow its logs
;; ::   g / r     refresh          a   toggle stopped containers
;; ::   y         copy its name    q   bury the buffer
;; ::   d         stop it          (C-u d -> kill it)
;; ::
;; :: `ps'/`dps' render into one reusable read-only buffer; `exec'/`logs' get a
;; :: vterm in the right-side split (same machinery the dev commands in web.el
;; :: use), so they're real interactive terminals -- C-c quits a log follow, and
;; :: the shell keeps running when the window is hidden.

(defvar my/docker-executable "docker"
  ":: Docker binary; resolved on PATH at call time.")

(defvar my/docker-dps-command "dps"
  ":: Fish alias run by `my/dps' -- defined in fish/config.fish.")

(defvar my/docker-logs-tail 200
  ":: Lines of history `my/docker-logs' shows before following.")

(defvar my/docker-exec-commands
  '("auto" "bash" "sh" "zsh" "fish")
  ":: Completion candidates for `my/docker-exec'. Not a closed set -- type any
command instead (e.g. `python manage.py shell'). \"auto\" runs bash when the
image has it and falls back to sh.")

(defvar my/docker-exec-auto-command
  "sh -c 'command -v bash >/dev/null 2>&1 && exec bash || exec sh'"
  ":: What \"auto\" expands to: prefer bash, fall back to sh (alpine images).")

(defvar my/docker-exec-history nil
  ":: Minibuffer history for `my/docker-exec' commands.")

;; ──────────────────────────────────────────────────────
;; :: Shelling out
;; ──────────────────────────────────────────────────────

(defun my/docker--program ()
  ":: Absolute path to the docker binary, or a clear error."
  (or (executable-find my/docker-executable)
      (user-error "docker not found on PATH")))

(defun my/docker--run (&rest args)
  ":: Run `docker ARGS...' synchronously and return stdout as a string.
stderr is captured too, so a stopped daemon surfaces as a readable error
(\"Cannot connect to the Docker daemon\") rather than an empty listing."
  (let ((docker (my/docker--program)))
    (with-temp-buffer
      (let ((status (apply #'call-process docker nil t nil args)))
        (unless (zerop status)
          (user-error "docker %s: %s"
                      (string-join args " ")
                      (or (car (split-string (string-trim (buffer-string)) "\n" t))
                          "failed")))
        (buffer-string)))))

(defun my/docker--dps-output ()
  ":: Output of the `dps' fish alias.
Shelled out to fish on purpose -- fish sources config.fish for non-interactive
shells too, so the alias stays the single source of truth for that format
instead of being duplicated here."
  (let ((fish (executable-find "fish")))
    (unless fish
      (user-error "fish not found on PATH -- `%s' is a fish alias" my/docker-dps-command))
    (with-temp-buffer
      (let ((status (call-process fish nil t nil "-c" my/docker-dps-command)))
        (unless (zerop status)
          (user-error "%s: %s" my/docker-dps-command
                      (or (car (split-string (string-trim (buffer-string)) "\n" t))
                          "failed")))
        (buffer-string)))))

;; ──────────────────────────────────────────────────────
;; :: Container listing + selection
;; ──────────────────────────────────────────────────────

(defun my/docker-containers (&optional all)
  ":: Containers as plists (:id :name :image :status). ALL includes stopped ones."
  (let* ((args (append '("ps")
                       (when all '("-a"))
                       '("--format" "{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}")))
         (out  (apply #'my/docker--run args)))
    (mapcar (lambda (line)
              (pcase-let ((`(,id ,name ,image ,status) (split-string line "\t")))
                (list :id id :name name :image image :status status)))
            (split-string out "\n" t))))

(defun my/docker--completion-table (containers)
  ":: Completion table over CONTAINERS' names, annotated with image + status.
Annotation (not a pre-formatted candidate string) keeps matching keyed on the
name alone, so typing `django' doesn't also match every container built from a
django image."
  (let ((names (mapcar (lambda (c) (plist-get c :name)) containers)))
    (lambda (str pred action)
      (if (eq action 'metadata)
          `(metadata
            (category . my/docker-container)
            (annotation-function
             . ,(lambda (name)
                  (when-let ((c (seq-find (lambda (x) (equal name (plist-get x :name)))
                                          containers)))
                    (format "   %s  %s"
                            (propertize (plist-get c :image) 'face 'font-lock-comment-face)
                            (propertize (plist-get c :status) 'face 'shadow))))))
        (complete-with-action action names str pred)))))

(defun my/docker--read-container (prompt &optional all)
  ":: Pick a container interactively; returns its plist."
  (let ((containers (my/docker-containers all)))
    (unless containers
      (user-error "No %scontainers" (if all "" "running ")))
    (let ((name (completing-read prompt (my/docker--completion-table containers)
                                 nil t)))
      (seq-find (lambda (c) (equal name (plist-get c :name))) containers))))

;; ──────────────────────────────────────────────────────
;; :: docker ps / dps  --  the listing buffer
;; ──────────────────────────────────────────────────────

(defvar-local my/docker-ps--source 'docker
  ":: Which listing this buffer shows: `docker' (docker ps) or `dps'.")

(defvar-local my/docker-ps--all nil
  ":: Non-nil when the listing includes stopped containers (docker ps -a).")

(define-derived-mode my/docker-ps-mode special-mode "Docker-ps"
  ":: Major mode for the *Docker ps* container listing.
Truncates lines -- the table is column-aligned and wrapping destroys it, same
reasoning as the db table viewers."
  (setq-local truncate-lines t)
  (buffer-disable-undo))

(defun my/docker-ps--header ()
  ":: Header line: what's being shown + the keys that act on it."
  (concat " " (if (eq my/docker-ps--source 'dps) "dps" "docker ps")
          (if my/docker-ps--all " -a" "")
          "   RET/e exec   l logs   d stop (C-u kill)   y copy   a all   g refresh   q bury"))

(defun my/docker-ps--render ()
  ":: (Re)fill the current listing buffer, keeping point on the same line."
  (let ((inhibit-read-only t)
        (line (line-number-at-pos)))
    (erase-buffer)
    (insert (if (eq my/docker-ps--source 'dps)
                (my/docker--dps-output)
              (apply #'my/docker--run (append '("ps") (when my/docker-ps--all '("-a"))))))
    (setq header-line-format (my/docker-ps--header))
    (goto-char (point-min))
    (forward-line (1- line))
    (set-buffer-modified-p nil)))

(defun my/docker-ps--show (source all)
  ":: Display the singleton listing buffer for SOURCE (`docker' or `dps')."
  (let ((buf (get-buffer-create "*Docker ps*")))
    (with-current-buffer buf
      (unless (derived-mode-p 'my/docker-ps-mode) (my/docker-ps-mode))
      (setq my/docker-ps--source source
            my/docker-ps--all   all)
      (my/docker-ps--render))
    (pop-to-buffer buf)))

;;;###autoload
(defun my/docker-ps (&optional all)
  ":: Show `docker ps' in a reusable buffer. With ALL (C-u), include stopped."
  (interactive "P")
  (my/docker-ps--show 'docker (and all t)))

;;;###autoload
(defun my/dps ()
  ":: Show the `dps' fish alias (short `docker ps') in the listing buffer."
  (interactive)
  (my/docker-ps--show 'dps nil))

(defun my/docker-ps-refresh ()
  ":: Re-run the current listing."
  (interactive)
  (my/docker-ps--render)
  (message "Refreshed"))

(defun my/docker-ps-toggle-all ()
  ":: Toggle stopped containers in the listing (docker ps <-> docker ps -a).
`dps' has its own fixed format, so toggling switches the listing to docker ps."
  (interactive)
  (setq my/docker-ps--all    (not my/docker-ps--all)
        my/docker-ps--source 'docker)
  (my/docker-ps--render)
  (message "Showing %s containers" (if my/docker-ps--all "all" "running")))

(defun my/docker-ps--container-at-point ()
  ":: The container on the current line, matched by its ID column.
Both listings put a (possibly truncated) container ID first, so we match on ID
prefix -- which also makes the header row fail cleanly."
  (let ((field (save-excursion
                 (beginning-of-line)
                 (when (looking-at "[ \t]*\\([^ \t\n]+\\)")
                   (match-string 1)))))
    (or (and field
             (seq-find (lambda (c)
                         (or (string-prefix-p field (plist-get c :id))
                             (equal field (plist-get c :name))))
                       (my/docker-containers t)))
        (user-error "No container on this line"))))

(defun my/docker-ps-exec ()
  ":: Exec into the container on this line."
  (interactive)
  (my/docker-exec--run (plist-get (my/docker-ps--container-at-point) :name)))

(defun my/docker-ps-logs ()
  ":: Follow the logs of the container on this line."
  (interactive)
  (my/docker-logs--run (plist-get (my/docker-ps--container-at-point) :name)))

(defun my/docker-ps-stop (&optional kill)
  ":: Stop the container on this line. With KILL (C-u), `docker kill' it instead.
Asks for confirmation first -- there's no undo for either."
  (interactive "P")
  (let* ((container (my/docker-ps--container-at-point))
         (name (plist-get container :name)))
    (when (yes-or-no-p (format "%s %s? " (if kill "Kill" "Stop") name))
      (my/docker--run (if kill "kill" "stop") name)
      (my/docker-ps--render)
      (message "%s %s" (if kill "Killed" "Stopped") name))))

(defun my/docker-ps-copy-name ()
  ":: Copy the container name on this line to the clipboard."
  (interactive)
  (let ((name (plist-get (my/docker-ps--container-at-point) :name)))
    (kill-new name)
    (gui-set-selection 'CLIPBOARD name)
    (message "Copied → %s" name)))

;; ──────────────────────────────────────────────────────
;; :: exec / logs  --  vterm side splits
;; ──────────────────────────────────────────────────────

(defun my/docker--require-vterm ()
  (unless (fboundp 'vterm)
    (user-error "vterm not loaded -- enable ':term vterm' in init.el")))

(defun my/docker--root ()
  ":: Where the vterm starts -- the project root when web.el is loaded."
  (if (fboundp 'my/project-root) (my/project-root) default-directory))

(defun my/docker--vterm-run (buf-name cmd)
  ":: Spawn BUF-NAME as a vterm and run CMD in it, then show + focus it.
Uses web.el's `my/vterm-create'/`my/vterm-display' so the buffer bypasses
Doom's popup system: hiding the window never kills the shell. The short timer
gives vterm time to start its shell before we type into it (same pattern as
`my/claude-code')."
  (my/docker--require-vterm)
  (my/vterm-create buf-name (my/docker--root))
  (my/dev-register-buffer (get-buffer buf-name))
  (run-with-timer 0.4 nil
                  (lambda ()
                    (when-let ((b (get-buffer buf-name)))
                      (with-current-buffer b
                        (vterm-send-string (concat cmd "\n"))))))
  (my/focus-window (my/vterm-display buf-name)))

(defun my/docker-exec--run (name)
  ":: Prompt for a command and `docker exec -it' it in container NAME.
Container names can't contain shell metacharacters, so no quoting is needed."
  (my/docker--require-vterm)
  (let* ((input (completing-read (format "Run in %s: " name)
                                 my/docker-exec-commands
                                 nil nil nil 'my/docker-exec-history "auto"))
         (cmd   (if (equal input "auto") my/docker-exec-auto-command input))
         ;; :: uniquely named -- several shells into one container is normal
         (buf-name (generate-new-buffer-name (format "*Docker exec [%s]*" name))))
    (my/docker--vterm-run buf-name
                          (format "%s exec -it %s %s"
                                  my/docker-executable name cmd))))

;;;###autoload
(defun my/docker-exec (&optional all)
  ":: `docker exec -it' into a container, in a vterm side split.
Pick the container, then a shell (bash/sh/zsh/fish, or \"auto\" to prefer bash
and fall back to sh) -- or just type the command you want to run. With ALL
\(C-u), stopped containers are offered too."
  (interactive "P")
  (my/docker--require-vterm)
  (my/docker-exec--run (plist-get (my/docker--read-container
                                   "Exec into container: " (and all t))
                                  :name)))

(defun my/docker-logs--run (name)
  ":: Follow NAME's logs in a vterm, reusing a live follower if there is one."
  (my/docker--require-vterm)
  (let* ((buf-name (format "*Docker logs [%s]*" name))
         (buf      (get-buffer buf-name)))
    (if (and buf (process-live-p (get-buffer-process buf)))
        (my/focus-window (my/vterm-display buf))
      (when buf
        (let ((kill-buffer-query-functions nil)) (kill-buffer buf)))
      (my/docker--vterm-run buf-name
                            (format "%s logs -f --tail %d %s"
                                    my/docker-executable my/docker-logs-tail name)))))

;;;###autoload
(defun my/docker-logs (&optional all)
  ":: `docker logs -f' a container in a vterm side split (C-c stops following).
With ALL (C-u), stopped containers are offered too -- their logs print and the
follow exits immediately."
  (interactive "P")
  (my/docker--require-vterm)
  (my/docker-logs--run (plist-get (my/docker--read-container
                                   "Follow logs of container: " (and all t))
                                  :name)))

;; ──────────────────────────────────────────────────────
;; :: Keys
;; ──────────────────────────────────────────────────────

;; :: special-mode buffers start in evil *motion* state, where the map below is
;; :: only half live -- force normal (same fix as `my/hn-mode').
(after! evil
  (evil-set-initial-state 'my/docker-ps-mode 'normal))

(map! :map my/docker-ps-mode-map
      :n "RET" #'my/docker-ps-exec
      :n "e"   #'my/docker-ps-exec
      :n "l"   #'my/docker-ps-logs
      :n "d"   #'my/docker-ps-stop
      :n "y"   #'my/docker-ps-copy-name
      :n "a"   #'my/docker-ps-toggle-all
      :n "g"   #'my/docker-ps-refresh
      :n "r"   #'my/docker-ps-refresh
      :n "q"   #'quit-window)
