;;; vault.el --- Obsidian-style vaults over the org/notes tree -*- lexical-binding: t; -*-

;; :: A "vault" is a self-contained org/notes tree living one level under
;; :: `my/vaults-root' -- ~/org-notes/Work/, ~/org-notes/Personal/, ... Exactly one
;; :: vault is active at a time and `my/notes-dir' points at it, so EVERYTHING
;; :: derived from `my/notes-dir' (denote notes, journal, agenda, projects,
;; :: finance, snippets, schema, org-brain) becomes vault-scoped for free.
;; ::
;; :: This file MUST load before config.el sets `org-directory' and before every
;; :: other module -- several of them capture `my/notes-dir' in a top-level
;; :: `defvar' at load time. See the `load!' right after the platform file.
;; ::
;; :: A directory only counts as a vault if it holds a `.vault' marker file.
;; :: Until you create one we run in "flat mode": `my/notes-dir' ==
;; :: `my/vaults-root', i.e. exactly the pre-vault behaviour. That keeps the whole
;; :: config working while ~500 files are being moved into vaults.

;; ──────────────────────────────────────────────────────
;; :: Active vault
;; ──────────────────────────────────────────────────────
;; :: `my/vaults-root' and `my/notes-dir' are declared in config.el (before the
;; :: platform files set the root for this machine); we only derive from them here.

(defconst my/vault-marker ".vault"
  ":: a directory counts as a vault iff it contains this file")

(defvar my/vault nil
  ":: name of the active vault (a directory name under `my/vaults-root'), or nil
   for flat mode. Set with `my/vault-switch'; persisted per-machine.")

(defconst my/vault-subdirs
  '("notes/" "notes/journal/" "agendas/" "projects/" "finance/" "snippets/" "templates/")
  ":: skeleton `my/vault-create' scaffolds and `my/vault-refresh' keeps present.
   finance.el only calls `make-directory' at load time, so a vault switch alone
   would otherwise leave a fresh vault missing finance/.")

(defconst my/vault-seed-files '("tasks.org" "meetings.org" "reminders.org")
  ":: files a vault needs to exist for the agenda + appt to have something to read")

;; ──────────────────────────────────────────────────────
;; :: Persistence -- one sexp on disk, per-machine (not in the repo, so the Mac
;; :: and Linux boxes can sit in different vaults). Same idiom as db-saved.el.
;; ──────────────────────────────────────────────────────
(defvar my/vault-state-file
  (expand-file-name "active-vault"
                    (or (bound-and-true-p doom-data-dir) user-emacs-directory))
  ":: file holding the active vault name")

(defun my/vault--persist ()
  ":: write the active vault name to disk"
  (with-temp-file my/vault-state-file
    (let ((print-length nil) (print-level nil))
      (prin1 my/vault (current-buffer)))))

(defun my/vault--read-state ()
  ":: read the persisted vault name, or nil"
  (when (file-exists-p my/vault-state-file)
    (with-temp-buffer
      (insert-file-contents my/vault-state-file)
      (ignore-errors (read (current-buffer))))))

;; ──────────────────────────────────────────────────────
;; :: Discovery
;; ──────────────────────────────────────────────────────
(defun my/vault-list ()
  ":: sorted names of every vault under `my/vaults-root'. Non-vault subdirs (the
   old flat tree -- notes/, projects/, ...) are skipped for want of a marker."
  (when (file-directory-p my/vaults-root)
    (sort (seq-filter
           (lambda (name)
             (file-exists-p
              (expand-file-name my/vault-marker
                                (expand-file-name name my/vaults-root))))
           (directory-files my/vaults-root nil "\\`[^.]"))
          #'string<)))

(defun my/vault-dir (&optional vault)
  ":: absolute directory of VAULT, defaulting to the active one. A nil vault (flat
   mode) resolves to `my/vaults-root' itself."
  (let ((vault (or vault my/vault)))
    (file-name-as-directory
     (if vault (expand-file-name vault my/vaults-root) my/vaults-root))))

(defun my/vault--resolve ()
  ":: pick the startup vault: the persisted one if it still exists, else the first
   on disk, else nil (flat mode). Never errors -- this runs during init."
  (let ((vaults (my/vault-list))
        (saved (my/vault--read-state)))
    (cond
     ((and saved (member saved vaults)) saved)
     ((and saved vaults)
      (message ":: vault %S no longer exists -- falling back to %S" saved (car vaults))
      (car vaults))
     (vaults (car vaults))
     (t nil))))

;; ──────────────────────────────────────────────────────
;; :: Refresh -- re-point every vault-relative path at the active vault
;; ──────────────────────────────────────────────────────
;; :: These modules capture `my/notes-dir' in a top-level `defvar' at load time
;; :: (finance.el:4, todo-agenda.el:8, inventory.el:4, reminders.el:19,
;; :: org-brain.el:3, schema.el:10). They're correct at startup -- this file loads
;; :: first -- but go stale on a switch, so we re-`setq' them. Add an entry here
;; :: whenever a new module derives a path from `my/notes-dir' in a defvar.
(defvar my/vault-rebind-alist
  '((org-brain-notes-dir   . "")             ;; :: the vault root itself
    (finance-directory     . "finance/")
    (todo-agenda-directory . "agendas/")
    (inventory-file        . "inventory.org")
    (my/reminders-file     . "reminders.org")
    (my/schema-file        . "schema.d.ts")
    (my/gitlab-issues-dir  . my/gitlab-issues-relative-dir))
  ":: alist of (SYMBOL . PATH-RELATIVE-TO-VAULT) rebound on every vault switch.
   PATH-RELATIVE-TO-VAULT is normally a string, but may be a 0-arg function
   symbol for paths that depend on other state (e.g. the gitlab project name)
   -- see `my/gitlab-issues-relative-dir' in modules/gitlab.el.")

(defun my/vault--ensure-dirs ()
  ":: create the vault skeleton if a switch landed us somewhere incomplete"
  (dolist (rel my/vault-subdirs)
    (let ((dir (expand-file-name rel my/notes-dir)))
      (unless (file-directory-p dir)
        (make-directory dir t)))))

(defun my/vault-refresh ()
  ":: point every vault-relative path at the active vault. Idempotent."
  (setq my/notes-dir (my/vault-dir))
  (my/vault--ensure-dirs)
  (setq org-directory my/notes-dir)
  ;; :: denote + journal (plain variables, read at call time)
  (setq denote-directory (expand-file-name "notes/" my/notes-dir))
  (setq denote-journal-directory (expand-file-name "journal" denote-directory))
  ;; :: the load-time defvars other modules captured
  (dolist (cell my/vault-rebind-alist)
    (let* ((sym (car cell))
           (spec (cdr cell))
           (rel (if (functionp spec) (funcall spec) spec)))
      ;; :: $SCHEMA_FILE / $GITLAB_ISSUES_DIR outrank the vault -- see
      ;; :: modules/schema.el:10 and modules/gitlab.el:29
      (when (and (boundp sym)
                 (not (and (eq sym 'my/schema-file) (getenv "SCHEMA_FILE")))
                 (not (and (eq sym 'my/gitlab-issues-dir) (getenv "GITLAB_ISSUES_DIR"))))
        (set sym (if (string-empty-p rel)
                     my/notes-dir
                   (expand-file-name rel my/notes-dir))))))
  ;; :: agenda is rebuilt from the new paths (and re-adds reminders.org, which
  ;; :: reminders.el only appends inside a one-shot `after! org')
  (when (fboundp 'my/org-agenda-refresh-files)
    (my/org-agenda-refresh-files))
  ;; :: appt's schedule is derived from `org-agenda-files', so it has to be
  ;; :: re-primed AFTER the rebuild above or notifications keep firing for the
  ;; :: vault we just left.
  (when (fboundp 'my/reminders-sync-appt)
    (my/reminders-sync-appt))
  ;; :: named src blocks come from the vault's own api.org
  (when (fboundp 'my/notes-lob-ingest)
    (my/notes-lob-ingest))
  (when (fboundp 'projectile-add-known-project)
    (projectile-add-known-project my/notes-dir))
  my/notes-dir)

;; ──────────────────────────────────────────────────────
;; :: Scoping a single command to a vault
;; ──────────────────────────────────────────────────────
(defun my/vault-call-in (vault fn)
  ":: call FN with every vault-relative path pointing at VAULT, without changing
   the active vault. Uses `dlet' because this file is lexically bound and denote
   may not have loaded yet -- a plain `let' would bind lexically and be ignored."
  ;; :: Load denote BEFORE binding, not lazily inside the `dlet'. denote-journal
  ;; :: is `:commands'-autoloaded, so a first call from inside the binding would
  ;; :: run its `:config' setq against our temporary value and lose it on exit,
  ;; :: leaving the global journal directory at denote's own default.
  (require 'denote nil t)
  (require 'denote-journal nil t)
  (let* ((dir (my/vault-dir vault))
         (notes (expand-file-name "notes/" dir)))
    (dlet ((my/notes-dir dir)
           (denote-directory notes)
           (denote-use-directory notes)   ;; :: denote's sanctioned creation override
           (denote-journal-directory (expand-file-name "journal" notes)))
      (funcall fn))))

(defmacro my/with-vault (vault &rest body)
  ":: run BODY scoped to VAULT (a vault name, or nil for the root)."
  (declare (indent 1))
  `(my/vault-call-in ,vault (lambda () ,@body)))

(defun my/vault--table (vaults)
  ":: completion table over VAULTS that preserves order, so the active vault stays
   first and RET accepts it under vertico (which otherwise re-sorts)."
  (lambda (str pred action)
    (if (eq action 'metadata)
        '(metadata (category . my/vault)
                   (display-sort-function . identity)
                   (cycle-sort-function . identity))
      (complete-with-action action vaults str pred))))

(defun my/vault-read (&optional prompt)
  ":: prompt for a vault with the active one preselected. Returns nil in flat mode
   and skips the prompt entirely when there's only one vault."
  (let ((vaults (my/vault-list)))
    (cond
     ((null vaults) nil)
     ((null (cdr vaults)) (car vaults))
     (t (let ((ordered (if (member my/vault vaults)
                           (cons my/vault (remove my/vault vaults))
                         vaults)))
          (completing-read (or prompt "Vault: ")
                           (my/vault--table ordered)
                           nil t nil nil (car ordered)))))))

;; ──────────────────────────────────────────────────────
;; :: Commands
;; ──────────────────────────────────────────────────────
(defun my/vault-switch (vault)
  ":: make VAULT active and re-point every derived path at it."
  (interactive
   (list (or (my/vault-read "Switch to vault: ")
             (user-error ":: no vaults yet -- create one with `my/vault-create'"))))
  (unless (member vault (my/vault-list))
    (user-error ":: %s is not a vault" vault))
  (setq my/vault vault)
  (my/vault--persist)
  (my/vault-refresh)
  (force-mode-line-update t)
  (message ":: vault -> %s (%s)" vault my/notes-dir))

(defun my/vault-create (name)
  ":: scaffold a new vault under `my/vaults-root' and switch to it."
  (interactive "sNew vault name: ")
  (let* ((name (string-trim name))
         (dir (file-name-as-directory (expand-file-name name my/vaults-root))))
    (when (string-empty-p name)
      (user-error ":: vault name cannot be empty"))
    (when (member name (my/vault-list))
      (user-error ":: vault %s already exists" name))
    (dolist (rel my/vault-subdirs)
      (make-directory (expand-file-name rel dir) t))
    (dolist (f my/vault-seed-files)
      (let ((path (expand-file-name f dir)))
        (unless (file-exists-p path)
          (with-temp-file path
            (insert (format "#+TITLE: %s\n\n" (capitalize (file-name-base f))))))))
    ;; :: projectile root, so `my/find-file-in-notes' / `my/search-notes' work
    ;; :: inside the vault the way they did at the old flat root
    (let ((p (expand-file-name ".projectile" dir)))
      (unless (file-exists-p p) (with-temp-file p (insert ""))))
    ;; :: marker last -- the vault only becomes visible once it's fully scaffolded
    (with-temp-file (expand-file-name my/vault-marker dir) (insert ""))
    (my/vault-switch name)))

(defun my/vault-browse ()
  ":: dired the vaults root"
  (interactive)
  (dired my/vaults-root))

(defun my/vault-grep-all ()
  ":: grep across EVERY vault's notes, ignoring the active one -- for when a note
   was filed in the wrong vault. Denote treats a list `denote-directory' as one
   expansive directory, so consult-denote handles this natively."
  (interactive)
  (require 'consult-denote nil t)
  (let ((dirs (mapcar (lambda (v) (expand-file-name "notes/" (my/vault-dir v)))
                      (my/vault-list))))
    (unless dirs (user-error ":: no vaults yet"))
    (dlet ((denote-directory dirs))
      (call-interactively #'consult-denote-grep))))

(defun my/vault-note ()
  ":: SPC n n -- pick a vault (active one preselected, so RET accepts), then run
   the usual denote open-or-create flow inside it."
  (interactive)
  (my/with-vault (my/vault-read "Note in vault: ")
    (call-interactively #'denote-open-or-create)))

(defun my/vault-journal ()
  ":: SPC n j / SPC d a -- today's journal entry in a prompted vault"
  (interactive)
  (my/with-vault (my/vault-read "Journal in vault: ")
    (call-interactively #'denote-journal-new-or-existing-entry)))

;; ──────────────────────────────────────────────────────
;; :: Modeline -- same `global-mode-string' pattern as the workspace segment
;; ──────────────────────────────────────────────────────
(defun my/vault-modeline-string ()
  (when my/vault
    (concat " " (propertize (format "(%s)" my/vault)
                            'face 'doom-modeline-buffer-major-mode))))

(add-to-list 'global-mode-string '(:eval (my/vault-modeline-string)) t)

;; ──────────────────────────────────────────────────────
;; :: Resolve the active vault NOW -- every module loaded after this point reads
;; :: `my/notes-dir' expecting it to already be the vault. No rebinding needed
;; :: here: nothing that derives from it has loaded yet.
;; ──────────────────────────────────────────────────────
(setq my/vault (my/vault--resolve)
      my/notes-dir (my/vault-dir))
(my/vault--ensure-dirs)

;; :: make EVERY vault reachable from `SPC p p', not just the active one
;; :: (config.el registers the active one; this adds the rest)
(after! projectile
  (dolist (name (my/vault-list))
    (projectile-add-known-project (my/vault-dir name))))

(map! :leader
      :prefix "n"
      :desc "Switch vault"       "v" #'my/vault-switch
      :desc "Grep all vaults"    "V" #'my/vault-grep-all
      :desc "Browse vaults root" "b" #'my/vault-browse)

(provide 'vault)
;;; vault.el ends here
