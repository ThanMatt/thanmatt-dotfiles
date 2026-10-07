;;; modules/claude.el -*- lexical-binding: t; -*-

(defvar my/claude-models
  '("sonnet" "opus" "haiku")
  ":: Model aliases for `claude --model'. The CLI resolves each alias to the
current model in that family, so this list never goes stale.")

(defvar my/claude-efforts
  '("low" "medium" "high" "xhigh" "max")
  ":: Effort levels accepted by claude --effort.")

;; ──────────────────────────────────────────────────────
;; :: herdr -- host the session in a herdr workspace instead of vterm
;; ──────────────────────────────────────────────────────
;; :: herdr's server listens on a unix socket and its CLI wraps that API with
;; :: JSON replies, so Emacs can drive it from outside like tmux. With no server
;; :: running every call here fails quietly and the vterm path is used as before.

(defconst my/claude--vterm-choice "Emacs (vterm)"
  ":: Workspace-prompt entry that keeps the session in the *claude-ask* buffer.")

(defun my/claude--herdr-call (&rest args)
  ":: Run `herdr ARGS...' and return its parsed JSON reply, or nil on failure.
Commands that print nothing on success (`pane run') return t. herdr reports
errors as JSON on stderr, which is discarded -- callers only need to know
whether it worked. JSON false/null parse to nil so tests read naturally."
  (when (executable-find "herdr")
    (with-temp-buffer
      (when (eq 0 (ignore-errors
                    (apply #'call-process "herdr" nil '(t nil) nil args)))
        (goto-char (point-min))
        (or (eobp)
            (ignore-errors
              (json-parse-buffer :object-type 'alist :array-type 'list
                                 :false-object nil :null-object nil)))))))

(defun my/claude--herdr-workspace ()
  ":: Ask which herdr workspace should host the session; nil means vterm.
Returns nil without asking when no herdr server is running (or the buffer is
remote, where the local tmpfile wouldn't be readable). The default is the
workspace labelled after the current project, else the one focused in herdr."
  (when-let* (((not (file-remote-p default-directory)))
              (status (my/claude--herdr-call "status" "server" "--json"))
              ((alist-get 'running status))
              (spaces (let-alist (my/claude--herdr-call "workspace" "list")
                        .result.workspaces)))
    (let* ((project (and (fboundp 'doom-project-name) (doom-project-name)))
           (cands   (mapcar (lambda (w)
                              (let-alist w (cons (format "%d: %s" .number .label) w)))
                            spaces))
           (default (car (or (seq-find (lambda (c) (equal (alist-get 'label (cdr c)) project))
                                       cands)
                             (seq-find (lambda (c) (alist-get 'focused (cdr c))) cands)
                             (car cands))))
           (choice  (completing-read "Run Claude in: "
                                     (append (mapcar #'car cands)
                                             (list my/claude--vterm-choice))
                                     nil t nil nil default)))
      (alist-get 'workspace_id (cdr (assoc choice cands))))))

(defun my/claude--run-in-herdr (workspace-id command)
  ":: Run COMMAND in a new, focused tab of herdr WORKSPACE-ID.
The tab starts in `default-directory', like the vterm buffer would. `pane run'
right after `tab create' is safe: the pty buffers it until the shell is up.
Failures are errors, not a vterm fallback -- once the tab exists, falling back
could start the same session twice."
  (let ((pane (let-alist (my/claude--herdr-call
                          "tab" "create" "--workspace" workspace-id
                          "--cwd" (expand-file-name default-directory)
                          "--label" "claude" "--focus")
                .result.root_pane.pane_id)))
    (unless pane
      (user-error "herdr: couldn't open a tab in %s" workspace-id))
    (unless (my/claude--herdr-call "pane" "run" pane command)
      (user-error "herdr: couldn't start claude in pane %s" pane))
    (message "Claude started in herdr pane %s" pane)))

(defun my/claude--run-in-vterm (command)
  ":: Run COMMAND in a fresh *claude-ask* vterm buffer."
  (let ((existing (get-buffer "*claude-ask*")))
    (when (and existing (buffer-live-p existing))
      (kill-buffer existing)))
  (let ((buf (get-buffer-create "*claude-ask*")))
    (pop-to-buffer buf)
    (vterm-mode)
    (run-with-timer 0.3 nil
                    (lambda ()
                      (when (buffer-live-p buf)
                        (vterm-send-string command)
                        (vterm-send-return))))))

;; ──────────────────────────────────────────────────────
;; :: resume -- org notes that record the session they came from
;; ──────────────────────────────────────────────────────
;; :: Notes written by Claude carry `#+session: <id>'. `claude --resume' only
;; :: finds a session from the profile and directory it ran in, so both are
;; :: recovered: the profile is whichever ~/.claude* holds the transcript, the
;; :: directory is read back from it. Emacs doesn't see the shell's

(defconst my/claude--default-config-dir (expand-file-name "~/.claude/")
  ":: The profile `claude' uses when CLAUDE_CONFIG_DIR is unset.")

(defun my/claude--profiles ()
  ":: Every profile directory: $CLAUDE_CONFIG_DIR plus each ~/.claude* directory."
  (delete-dups
   (mapcar #'file-name-as-directory
           (seq-filter #'file-directory-p
                       (delq nil (cons (getenv "CLAUDE_CONFIG_DIR")
                                       (file-expand-wildcards "~/.claude*" t)))))))

(defun my/claude--pick-profile ()
  ":: Ask which profile a new session should use; returns its directory.
Doesn't ask when there is only one. The default is $CLAUDE_CONFIG_DIR when
set, else the plain `claude' profile."
  (let* ((dirs  (my/claude--profiles))
         (cands (mapcar (lambda (d) (cons (abbreviate-file-name (directory-file-name d)) d))
                        dirs))
         (env   (getenv "CLAUDE_CONFIG_DIR"))
         (fallback (file-name-as-directory (or env my/claude--default-config-dir))))
    (if (cdr cands)
        (cdr (assoc (completing-read "Profile: " (mapcar #'car cands) nil t nil nil
                                     (car (rassoc fallback cands)))
                    cands))
      (or (car dirs) fallback))))

(defun my/claude--find-session (id)
  ":: Locate session ID as (CONFIG-DIR . CWD), or nil if no profile has it."
  (when-let* ((dirs (my/claude--profiles))
              (hit (seq-some (lambda (d)
                               (when-let* ((f (car (file-expand-wildcards
                                                    (expand-file-name
                                                     (format "projects/*/%s.jsonl" id) d)))))
                                 (cons d f)))
                             dirs)))
    (with-temp-buffer
      ;; :: Every record carries cwd; the head of the file is enough.
      (insert-file-contents (cdr hit) nil 0 262144)
      (when (re-search-forward "\"cwd\":\"\\([^\"]+\\)\"" nil t)
        (cons (car hit) (file-name-as-directory (match-string 1)))))))

(defun my/claude--resume-session ()
  ":: In an org buffer with a `#+session:' keyword, offer to resume it.
Returns (ID CONFIG-DIR . CWD) when the user picks resume, nil for a new
session or when the buffer records no session."
  (when-let* (((derived-mode-p 'org-mode))
              (id (cadr (assoc "SESSION" (org-collect-keywords '("SESSION")))))
              ((not (string-blank-p id)))
              (resume (format "Resume %s" id))
              ((equal (completing-read "Session: " (list resume "New session")
                                       nil t nil nil resume)
                      resume)))
    (cons id (or (my/claude--find-session id)
                 (user-error "Session %s not found under ~/.claude*/projects" id)))))

(defun my/claude--command (config &optional id)
  ":: The `claude' invocation for profile CONFIG, resuming session ID when non-nil.
A non-default profile is selected with CLAUDE_CONFIG_DIR; the default one is
left unset, since setting it also moves where claude looks for .claude.json."
  (concat (unless (equal config my/claude--default-config-dir)
            (format "env CLAUDE_CONFIG_DIR=%s "
                    (shell-quote-argument (directory-file-name config))))
          "claude"
          (when id (concat " --resume " (shell-quote-argument id)))))

(defun my/claude-ask-region (start end)
  ":: Open an interactive Claude session with the selected region as context.
In an org note with a `#+session:' keyword, first asks whether to resume that
session (in the profile and directory it ran in) or start a new one; a new
session asks which ~/.claude* profile to use when there is more than one. When a
herdr server is running, then asks which herdr workspace should host the
session (or Emacs, for the vterm buffer). Then prompts for model, effort, and query in sequence.
Empty query defaults to 'Explain this snippet.'
Runs: [env CLAUDE_CONFIG_DIR=<profile>] claude [--resume <id>] --model <model> --effort <effort> \"$(cat tmpfile)\""
  (interactive "r")
  (let* ((code   (buffer-substring-no-properties start end))
         (file   (or (buffer-file-name) (buffer-name)))
         (line   (line-number-at-pos start))
         (session (my/claude--resume-session))
         (config (if session (cadr session) (my/claude--pick-profile)))
         (default-directory (or (cddr session) default-directory))
         (herdr  (my/claude--herdr-workspace))
         (model  (completing-read "Model: " my/claude-models nil t nil nil "sonnet"))
         (effort (completing-read "Effort: " my/claude-efforts nil t nil nil "medium"))
         (input  (read-string "Ask Claude (RET to explain): "))
         (query  (if (string-blank-p input) "Explain this snippet." input))
         (prompt (format "File: %s:%d\n\n```\n%s\n```\n\n%s" file line code query))
         (tmp    (make-temp-file "claude-ctx-" nil ".txt"))
         (cmd    (format "%s --model %s --effort %s \"$(cat %s)\""
                         (my/claude--command config (car session))
                         (shell-quote-argument model)
                         (shell-quote-argument effort)
                         (shell-quote-argument tmp))))
    (with-temp-file tmp (insert prompt))
    (if herdr
        (my/claude--run-in-herdr herdr cmd)
      (my/claude--run-in-vterm cmd))))
