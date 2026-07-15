;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; Place your private configuration here! Remember, you do not need to run 'doom
;; sync' after modifying this file!

;; :: GUI Emacs (launched from sway) never sources Fish, so asdf isn't on PATH.
;; :: Shims call `asdf exec', which needs ASDF_DIR set and ~/.asdf/bin on PATH.
;; :: Without both, apheleia-npx (and other asdf-managed tools) fail with 127.
(let ((asdf-dir    (expand-file-name "~/.asdf"))
      (asdf-bin    (expand-file-name "~/.asdf/bin"))
      (asdf-shims  (expand-file-name "~/.asdf/shims")))
  (when (file-directory-p asdf-dir)
    (setenv "ASDF_DIR" asdf-dir)
    (dolist (dir (list asdf-bin asdf-shims))
      (add-to-list 'exec-path dir)
      (setenv "PATH" (concat dir path-separator (getenv "PATH"))))))

;; ──────────────────────────────────────────────────────
;; :: Notes / org root -- per-machine
;; ──────────────────────────────────────────────────────
;; :: Single source of truth for the org/notes tree. The real value is set
;; :: per-machine in the OS files just below -- ~/notes/ on macOS, ~/org-notes/
;; :: on Linux -- and everything note-related (org-directory, agenda, snippets,
;; :: brain, schema, finance, ...) derives from it, so relocating the whole tree
;; :: is a one-line change. The default here is only a fallback.
(defvar my/notes-dir (expand-file-name "~/notes/")
  ":: Root of my org/notes tree; overridden per-machine in +macos.el / +linux.el.")

;; :: Load OS-specific config EARLY -- on macOS this imports shell env vars
;; :: (GITLAB_*, PROJECT_SEARCH_PATHS, ...) via exec-path-from-shell before the
;; :: `load!'s below read them. Linux sets the Wayland clipboard + shell path.
;; :: (The OS files also set `my/notes-dir' for that machine.)
(if (featurep :system 'macos)
    (load! "+macos")
  (load! "+linux"))

;; ──────────────────────────────────────────────────────
;; :: Soft word wrap (:editor word-wrap)
;; ──────────────────────────────────────────────────────
;; :: Wrap long lines at word boundaries (with language-aware indent) in every
;; :: buffer -- EXCEPT the db table viewers. Those render wide, column-aligned
;; :: tables; wrapping shifts cells onto the next line and destroys the layout,
;; :: so they keep `truncate-lines' (set in their own modes). `+word-wrap-mode'
;; :: still toggles per-buffer if I want wrap somewhere it's excluded.
;; ::
;; :: NOT wrapped in `after! word-wrap' -- the word-wrap module never (provide)s a
;; :: `word-wrap' feature, so that body never runs (which is why the global mode
;; :: wasn't taking and only a manual `SPC t w' worked). This file loads after all
;; :: module config.el, so the var + globalized mode already exist: call directly.
;; :: `+global-word-wrap-mode' already skips `special-mode' buffers and the db
;; :: result/colsel modes derive from special-mode, so listing them is belt-and-
;; :: suspenders -- kept for clarity and in case a viewer stops being special.
(dolist (mode '(my/sql-result-mode my/sql-colsel-mode))
  (add-to-list '+word-wrap-disabled-modes mode))
(+global-word-wrap-mode +1)

;; ──────────────────────────────────────────────────────
;; :: TypeScript / TSX engine  --  web-mode  <->  tree-sitter
;; ──────────────────────────────────────────────────────
;; :: Doom's :lang javascript maps .tsx -> tsx-ts-mode (tree-sitter), but the
;; :: Arch libtree-sitter 0.26 / Emacs 30.2 predicate-query incompat makes that
;; :: grammar unreliable -- files intermittently fall back to a non-JSX mode, so
;; :: the LSP parses them as plain .ts and reports "cannot find name 'div'".
;; :: Route .tsx/.jsx to a web-mode-based major mode instead (no grammar dep).
;; :: A dedicated derived mode keeps it distinct from HTML web-mode, so we can
;; :: map it to the "typescriptreact" language-id (below) without touching the
;; :: language-id of actual HTML web-mode buffers.
(define-derived-mode typescript-tsx-mode web-mode "TSX"
  ":: web-mode-based major mode for .tsx/.jsx -- no tree-sitter.")

;; :: web-mode is the default (proven everywhere). On macOS, tree-sitter loads
;; :: cleanly, so `my/tsx-toggle-treesit' (SPC d x) can flip to tsx-ts-mode for
;; :: incremental parsing; on Linux that toggle just stays on web-mode. Default
;; :: nil keeps the safe path so a grammar mismatch can never brick .tsx editing.
(defvar my/tsx-use-treesit nil
  ":: Non-nil routes .ts/.tsx/.jsx to tree-sitter modes; nil uses web-mode.")

(defun my/tsx-mode-routing ()
  ":: Point `auto-mode-alist' AND `major-mode-remap-alist' at the engine
`my/tsx-use-treesit' selects. Strips our prior entries first so the toggle is
idempotent, then prepends the chosen pair.

The remap is the belt-and-suspenders part. `auto-mode-alist' alone is not
enough: Doom's :lang javascript (and Emacs' own autoloads) re-assert a
.tsx -> tsx-ts-mode entry after this file loads, so the first file we open gets
web-mode but later ones can slip into the (broken-on-Linux) tree-sitter mode.
`set-auto-mode' funnels EVERY mode choice through `major-mode-remap-alist' last,
so forcing tsx-ts-mode -> typescript-tsx-mode there makes a stray tree-sitter
buffer impossible while the engine is web-mode."
  (setq auto-mode-alist
        (cl-remove-if (lambda (e) (member (car e) '("\\.[tj]sx\\'" "\\.ts\\'")))
                      auto-mode-alist))
  (dolist (entry (if my/tsx-use-treesit
                     '(("\\.ts\\'"     . typescript-ts-mode)
                       ("\\.[tj]sx\\'" . tsx-ts-mode))
                   '(("\\.ts\\'"     . typescript-mode)
                     ("\\.[tj]sx\\'" . typescript-tsx-mode))))
    (push entry auto-mode-alist))
  ;; :: Force (web-mode) or clear (tree-sitter) the ts-mode -> web-mode remap.
  (dolist (pair '((tsx-ts-mode        . typescript-tsx-mode)
                  (typescript-ts-mode . typescript-mode)))
    (setq major-mode-remap-alist (assq-delete-all (car pair) major-mode-remap-alist))
    (unless my/tsx-use-treesit
      (push pair major-mode-remap-alist))))

(defun my/tsx-toggle-treesit ()
  ":: Flip the TSX engine and re-open visiting buffers in the new major mode."
  (interactive)
  (setq my/tsx-use-treesit (not my/tsx-use-treesit))
  (my/tsx-mode-routing)
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when (and buffer-file-name
                 (string-match-p "\\.[tj]sx?\\'" buffer-file-name)
                 (memq major-mode '(typescript-tsx-mode typescript-mode
                                    tsx-ts-mode typescript-ts-mode web-mode)))
        (let ((inhibit-message t)) (normal-mode)))))
  (message "TSX engine: %s" (if my/tsx-use-treesit
                                "tree-sitter (tsx-ts-mode)"
                              "web-mode")))

(my/tsx-mode-routing)

;; :: vtsls (not the default ts-ls / typescript-language-server): it wraps VS
;; :: Code's TS engine and correctly resolves Vite "solution-style" tsconfigs
;; :: (root tsconfig.json with `files: []` + `references`), which ts-ls does not
;; :: -- that fallback turns jsx off + implicit-any on and floods every <div>
;; :: with bogus diagnostics. lsp-vtsls (packages.el) registers at :priority -1,
;; :: beating ts-ls (-2), so lsp-mode auto-selects it; the binary is found on
;; :: PATH (asdf shim, added to exec-path above) via its :system dependency.
;; :: Install the server if it's missing: M-x lsp-install-server RET vtsls.
(use-package! lsp-vtsls :after lsp-mode)

;; :: lsp-mode keys client activation + the language-id it sends off
;; :: `lsp-buffer-language', which it derives from `lsp-language-id-configuration'.
;; :: Our web-mode-derived TSX mode isn't in that alist, so map it explicitly --
;; :: without this lsp-buffer-language is nil and NEITHER vtsls nor tailwindcss
;; :: activates. (.ts -> typescript-mode is already mapped by lsp-mode.)
(after! lsp-mode
  (add-to-list 'lsp-language-id-configuration
               '(typescript-tsx-mode . "typescriptreact")))

;; :: Doom only attaches the LSP client to the modes its javascript module
;; :: manages; our web-mode-based TSX mode needs the hook added explicitly.
;; :: `lsp!' starts whichever backend is configured (lsp-mode or eglot).
(add-hook 'typescript-tsx-mode-local-vars-hook #'lsp!)
(add-hook 'typescript-mode-local-vars-hook     #'lsp!)
;; :: tree-sitter modes (used when `my/tsx-use-treesit' is on) need it too.
(add-hook 'tsx-ts-mode-local-vars-hook         #'lsp!)
(add-hook 'typescript-ts-mode-local-vars-hook  #'lsp!)

;; ──────────────────────────────────────────────────────
;; :: TSX typing performance (web-mode + lsp-mode)
;; ──────────────────────────────────────────────────────
;; :: In a .tsx buffer every keystroke triggers web-mode's after-change scan,
;; :: an lsp-mode didChange, a corfu completion query and an eldoc hover. web-mode
;; :: also runs per-keystroke transformers we don't need (smartparens already
;; :: pairs/quotes). Turning these off is what removes the typing lag.
(after! web-mode
  (setq web-mode-enable-auto-quoting nil        ; :: no "" insertion after = (re-scans)
        web-mode-enable-auto-pairing nil        ; :: smartparens handles pairs already
        web-mode-enable-auto-indentation nil    ; :: reindent-on-type is expensive
        web-mode-enable-auto-expanding nil
        web-mode-enable-css-colorization nil    ; :: stop scanning for color literals
        web-mode-enable-current-element-highlight nil
        web-mode-enable-current-column-highlight nil))

;; :: web-mode re-scans + refontifies the *enclosing JSX block* on every edit, so
;; :: the cost grows with how deeply nested the JSX at point is. web-mode has no
;; :: incremental parser, so we take fontification off the keystroke's critical
;; :: path instead: the char is inserted immediately and colors catch up ~50ms
;; :: later when typing pauses.
(defun my/tsx-typing-perf ()
  ":: Buffer-local latency tweaks for deeply-nested JSX in web-mode TSX buffers."
  (setq-local jit-lock-defer-time 0.05      ; :: defer font-lock; don't run per-key
              jit-lock-stealth-time nil      ; :: no background full-buffer fontify
              web-mode-jsx-depth-faces nil)) ; :: skip per-depth JSX bg shading (costly)
(add-hook 'typescript-tsx-mode-hook #'my/tsx-typing-perf)

;; ──────────────────────────────────────────────────────
;; :: tailwindcss-language-server (lsp-mode add-on)
;; ──────────────────────────────────────────────────────
;; :: `add-on-mode' runs tailwindcss ALONGSIDE the primary TS server (vtsls)
;; :: instead of competing to be the buffer's single server -- which is the whole
;; :: reason we're on lsp-mode here. (eglot is one-server-per-buffer: the old
;; :: second-eglot-server hack returned "No Match" because tailwind never
;; :: received didOpen/didChange and so had no document to complete against.)
;; :: `add-on-mode' is read when the client registers, so it must be set in
;; :: `:init' (runs at startup), not `:config' (too late). The client activates
;; :: when `major-mode' is (derived from one) in `lsp-tailwindcss-major-modes' --
;; :: default already covers web-mode + typescript-tsx-mode -- AND the project has
;; :: a tailwind.config.* (anywhere in the tree) or a v4 tailwind dependency.
;; :: Let lsp-mode MANAGE the server: the client runs `node <server-path> --stdio',
;; :: so server-path MUST be a JS file. Do NOT set it to the asdf
;; :: `tailwindcss-language-server' shim -- that's a bash script, and `node <bash>'
;; :: dies instantly with "SyntaxError: Invalid or unexpected token" (exit 1, the
;; :: endless "restart? y/n" loop). With server-path unset, lsp downloads
;; :: bradlc.vscode-tailwindcss's tailwindServer.js into its own dir and runs that.
;; :: Install once: `M-x lsp-install-server RET tailwindcss'. tailwind handles the
;; :: "typescriptreact" language-id natively, so no includeLanguages remap.
(use-package! lsp-tailwindcss
  :after lsp-mode
  :init (setq lsp-tailwindcss-add-on-mode t))

;; ──────────────────────────────────────────────────────
;; :: LSP file watching -- keep the watch set small
;; ──────────────────────────────────────────────────────
;; :: lsp-mode watches the workspace so vtsls hears about on-disk changes made
;; :: outside Emacs (branch switch, npm install, codegen). A frontend repo trips
;; :: the default 1000-file threshold -- which slows Emacs and (on Linux) can
;; :: exhaust inotify watches -- so exclude build/output/cache dirs. With the
;; :: count under threshold, lsp also stops asking "watch all files?" on open.
(after! lsp-mode
  (setq lsp-file-watch-threshold 2000)
  (dolist (dir '("[/\\\\]node_modules\\'"
                 "[/\\\\]\\.next\\'"
                 "[/\\\\]dist\\'"
                 "[/\\\\]build\\'"
                 "[/\\\\]out\\'"
                 "[/\\\\]coverage\\'"
                 "[/\\\\]\\.turbo\\'"
                 "[/\\\\]\\.cache\\'"))
    (add-to-list 'lsp-file-watch-ignored-directories dir)))

;; Some functionality uses this to identify you, e.g. GPG configuration, email
;; clients, file templates and snippets. It is optional.
;; (setq user-full-name "John Doe"
;;       user-mail-address "john@doe.com")

;; ──────────────────────────────────────────────────────
;; :: Appearance -- font, theme, line numbers
;; ──────────────────────────────────────────────────────
;; :: `doom-font' is set per-machine in +macos.el / +linux.el (macOS defaults to
;; :: Cascadia Code, Arch to FiraCode Nerd Font) -- both files keep the other
;; :: family commented out for an easy switch. The `load!'s at the top of this
;; :: file run before this block, so setting the font there (not here) wins.

(setq doom-gruvbox-dark-variant "medium")
(setq doom-theme 'doom-gruvbox)

;; :: Relative line numbers (set to nil to disable, t for absolute).
(setq display-line-numbers-type 'relative)

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory my/notes-dir)

(menu-bar-mode -1)
(setq org-image-actual-width '(400))
;; :: org-agenda-files is set in modules/org-agenda.el (single source of truth).

;; ──────────────────────────────────────────────────────
;; :: Shell / vterm
;; ──────────────────────────────────────────────────────
;; :: bash for internal Emacs processes; the interactive vterm shell (Fish) is
;; :: set per-OS in +macos.el / +linux.el (Homebrew vs FHS path).
(setq shell-file-name (executable-find "bash"))

;; :: Keep vterm buffers alive even after their shell process exits, so the
;; :: reuse-by-name logic in web.el always has something to surface.
(after! vterm
  (setq vterm-kill-buffer-on-exit nil))

;; :: Kill line numbers in terminals. With relative line numbers the gutter
;; :: recomputes on every cursor move -- a full redraw per keystroke (the
;; :: "seizure" flicker). Terminals don't need line numbers.
(add-hook 'vterm-mode-hook (lambda () (display-line-numbers-mode -1)))

;; :: Don't let Doom's popup manager own our project terminals -- popups are
;; :: killed when their window closes. With `:ignore t' they use normal window
;; :: display (the side split in web.el) and closing only hides the buffer.
(set-popup-rule! "^\\*\\(?:Claude Code\\|Docker\\|vterm\\) " :ignore t)

;; :: Scrub inherited Claude Code session vars. If `doom env' is ever run from a
;; :: shell inside a Claude Code session, it freezes CLAUDE_CODE_* into
;; :: ~/.config/emacs/.local/env, which Doom loads at startup. vterm then hands
;; :: them to every shell, so `claude' launches see CLAUDE_CODE_CHILD_SESSION=1
;; :: and run as a nested child session -- no resumable transcript is written to
;; :: ~/.claude/projects. Unsetting them here makes every terminal start a clean,
;; :: top-level session regardless of what the env snapshot captured.
(dolist (v '("CLAUDECODE" "CLAUDE_CODE_CHILD_SESSION" "CLAUDE_CODE_SESSION_ID"
             "CLAUDE_CODE_ENTRYPOINT" "CLAUDE_CODE_EXECPATH" "CLAUDE_EFFORT"
             "AI_AGENT"))
  (setenv v nil))

;; ──────────────────────────────────────────────────────
;; :: Org -- export, babel, project scaffolding
;; ──────────────────────────────────────────────────────
(defun my/create-project (project-name)
  "Create a new project structure with template files."
  (interactive "sProject name: ")
  (let ((project-dir (expand-file-name
                      (concat "projects/" project-name) my/notes-dir)))
    (make-directory project-dir t)
    (with-temp-file (concat project-dir "/project.org")
      (insert (format "#+TITLE: %s\n#+AUTHOR: Your Name\n#+DATE: %s\n\n* Overview\n\n* Goals\n- [ ] \n\n* Tasks\n** TODO \n\n* Resources\n\n* Notes\n"
                      project-name
                      (format-time-string "%Y-%m-%d"))))
    (find-file (concat project-dir "/project.org"))))

(setq org-export-show-temporary-export-buffer nil)
(defun my/org-export-html-open ()
  (interactive)
  (org-html-export-to-html)
  (browse-url (concat "file://" (expand-file-name (org-export-output-file-name ".html")))))
(global-set-key (kbd "C-c e h") #'my/org-export-html-open)

;; :: Specify python command explicitly (harmless when :lang python is off).
(after! org
  (setq org-babel-python-command "python3")
  (setq python-shell-interpreter "python3")
  (setq python-shell-completion-native-enable nil)
  (setq python-shell-prompt-detect-failure-warning nil))
(org-babel-do-load-languages
 'org-babel-load-languages
 '((emacs-lisp . t)
   (python     . t)
   (shell      . t)
   (js         . t)))

(setq +doom-dashboard-ascii-banner-fn #'my/simple-banner)
(defun my/simple-banner ()
  '("                                    "
    "    Welcome to My Emacs Setup!     "
    "                                    "
    "         Ready to code...           "
    "                                    "))

;; ──────────────────────────────────────────────────────
;; :: Org block wrapping + link helpers
;; ──────────────────────────────────────────────────────
(defun my/org-wrap-quote ()
  "Wrap selected region in #+begin_quote / #+end_quote."
  (interactive)
  (if (use-region-p)
      (let ((start (region-beginning))
            (end (region-end)))
        (goto-char end)
        (insert "\n#+end_quote")
        (goto-char start)
        (insert "#+begin_quote\n")
        (deactivate-mark))
    (message "No region selected")))

(defun my/org-wrap-src ()
  "Wrap selected region in #+begin_src / #+end_src."
  (interactive)
  (if (use-region-p)
      (let ((start (region-beginning))
            (end (region-end)))
        (goto-char end)
        (insert "\n#+end_src")
        (goto-char start)
        (insert "#+begin_src\n")
        (deactivate-mark))
    (message "No region selected")))

(defun +org/sanitize-link-description (desc)
  ":: Escape square brackets in an org link description.
Org link descriptions cannot contain unescaped ] characters."
  (replace-regexp-in-string "\\]" "\\\\]"
                            (replace-regexp-in-string "\\[" "\\\\[" desc)))

(defun link-file (file)
  ":: Interactively select a file and insert it as an org hyperlink.
The link target uses a path relative to the current buffer when possible,
and the description is the file's basename with [ and ] escaped."
  (interactive
   (list (read-file-name "Link to file: " nil nil t)))
  (unless (derived-mode-p 'org-mode)
    (user-error "link-file only works in org-mode buffers"))
  (let* ((target (if buffer-file-name
                     (file-relative-name file (file-name-directory buffer-file-name))
                   (expand-file-name file)))
         (desc (+org/sanitize-link-description (file-name-nondirectory file))))
    (insert (format "[[file:%s][%s]]" target desc))))
(defalias '+org/insert-file-link #'link-file)

;; :: Copy highlighted region as an org-mode file link with line number.
;; :: Link format: [[file:/abs/path::LINE][description]]
(defun my/copy-region-as-org-link ()
  "Copy the selected region as an org-mode link pointing to its file and line.
Paste the result into any org file; following the link jumps to that exact line."
  (interactive)
  (unless (use-region-p)
    (user-error "No region selected — highlight some text first"))
  (let* ((file (buffer-file-name))
         (_ (unless file (user-error "Buffer is not visiting a file")))
         (line (line-number-at-pos (region-beginning)))
         (description (format "%s:%d" (file-name-nondirectory file) line))
         (link (format "[[file:%s::%d][%s]]" file line description)))
    (kill-new link)
    (gui-set-selection 'CLIPBOARD link)
    (message "Copied → %s" link)))

;; :: Copy the current buffer's file name / directory to the clipboard.
;; :: Same kill-ring + CLIPBOARD pairing as `my/copy-region-as-org-link' so the
;; :: result is yankable in Emacs and pasteable in any external app.
(defun my/copy-buffer-file-name ()
  "Copy the current buffer's file name (basename) to the clipboard."
  (interactive)
  (let ((file (buffer-file-name)))
    (unless file (user-error "Buffer is not visiting a file"))
    (let ((name (file-name-nondirectory file)))
      (kill-new name)
      (gui-set-selection 'CLIPBOARD name)
      (message "Copied → %s" name))))

(defun my/copy-buffer-directory ()
  "Copy the directory containing the current buffer's file to the clipboard."
  (interactive)
  (let ((file (buffer-file-name)))
    (unless file (user-error "Buffer is not visiting a file"))
    (let ((dir (directory-file-name (file-name-directory file))))
      (kill-new dir)
      (gui-set-selection 'CLIPBOARD dir)
      (message "Copied → %s" dir))))

;; ──────────────────────────────────────────────────────
;; :: Projects / Projectile
;; ──────────────────────────────────────────────────────
;; :: Project search roots. Set PROJECT_SEARCH_PATHS to a colon-separated list
;; :: of dirs (e.g. in ~/.config/fish/conf.d/local.fish) to point Projectile at
;; :: your real project trees; falls back to ~/dev/ when unset.
(setq projectile-project-search-path
      (let ((paths (getenv "PROJECT_SEARCH_PATHS")))
        (if (and paths (not (string-empty-p paths)))
            (split-string paths ":" t)
          '("~/dev/"))))

(defun my/activate-venv ()
  ":: Find and activate a .venv or venv dir at/above the current directory."
  (interactive)
  (if-let* ((root (locate-dominating-file
                   default-directory
                   (lambda (dir)
                     (or (file-directory-p (expand-file-name ".venv" dir))
                         (file-directory-p (expand-file-name "venv" dir))))))
            (venv (seq-find #'file-directory-p
                            (list (expand-file-name ".venv" root)
                                  (expand-file-name "venv" root)))))
      (progn
        (pyvenv-activate venv)
        (message "Activated venv: %s" venv))
    (message "No .venv or venv found above %s" default-directory)))

(defun my/smart-lookup ()
  "Show LSP documentation if available, otherwise use default lookup."
  (interactive)
  (if (bound-and-true-p lsp-mode)
      (lsp-ui-doc-glance)
    (+lookup/documentation (thing-at-point 'symbol))))

(defun my/reference-project-file ()
  "Select a project, pick a file from it, and insert an org-mode link at cursor."
  (interactive)
  (let* ((project-dir (projectile-completing-read
                       "Select project: "
                       projectile-known-projects))
         (default-directory project-dir)
         (file (projectile-completing-read
                "Select file: "
                (projectile-project-files project-dir)))
         (file-path (expand-file-name file project-dir)))
    (insert (format "[[file:%s][%s]]" file-path (file-name-nondirectory file)))))

(defun my/find-file-in-notes ()
  "Find file recursively in the notes directory."
  (interactive)
  (let ((default-directory my/notes-dir))
    (call-interactively #'projectile-find-file)))

(defun my/search-notes ()
  "Search in the notes directory using ripgrep."
  (interactive)
  (let ((default-directory my/notes-dir))
    (call-interactively #'+default/search-project)))

(after! projectile
  (projectile-add-known-project my/notes-dir))

;; ──────────────────────────────────────────────────────
;; :: Org file-apps + extra TS niceties
;; ──────────────────────────────────────────────────────
(after! org
  (org-babel-lob-ingest (expand-file-name "api.org" my/notes-dir))
  (add-to-list 'org-file-apps '("\\.ts\\'" . emacs))
  (add-to-list 'org-file-apps '("\\.d\\.ts\\'" . emacs)))
(add-to-list 'auto-mode-alist '("\\.d\\.ts\\'" . typescript-ts-mode))

;; ──────────────────────────────────────────────────────
;; :: org-modern -- modern org-mode styling
;; ──────────────────────────────────────────────────────
;; :: Globally enable in org buffers + agenda. `org-modern-mode' restyles
;; :: bullets/headings/tags/blocks; the agenda hook styles the agenda view.
(use-package! org-modern
  :hook ((org-mode . org-modern-mode)
         (org-agenda-finalize . org-modern-agenda))
  ;; :: Default `org-modern-star' is 'fold, whose triangle glyphs (e.g. ⯈
  ;; :: U+2BC8) Fira Code lacks -- they render as tofu. Use 'replace with
  ;; :: round bullets Fira Code covers cleanly.
  :config
  (setq org-modern-star 'replace
        org-modern-replace-stars "◉○◈◇✳"
        ;; :: Per-priority badge colors in org buffers. Without this org-modern
        ;; :: paints every [#x] cookie with the single `org-modern-priority' face
        ;; :: (red). Keys are the priority chars; values are face plists.
        org-modern-priority-faces
        '((?A :foreground "white" :background "#ff6c6b" :weight bold)
          (?B :foreground "black" :background "#ECBE7B" :weight bold)
          (?C :foreground "black" :background "#98be65" :weight bold)))
  ;; :: Same colors for the agenda (org-modern-agenda doesn't restyle priorities;
  ;; :: the agenda reads the built-in `org-priority-faces').
  (setq org-priority-faces
        '((?A . (:foreground "#ff6c6b" :weight bold))
          (?B . (:foreground "#ECBE7B" :weight bold))
          (?C . (:foreground "#98be65" :weight bold)))))

;; ──────────────────────────────────────────────────────
;; :: org-appear -- reveal markup at point (pairs with org-modern)
;; ──────────────────────────────────────────────────────
;; :: org-modern hides emphasis markers/link brackets for a clean read; on its
;; :: own that makes editing them guesswork. org-appear toggles the raw markup
;; :: back on only while point is inside the element, then re-hides on exit.
(use-package! org-appear
  :hook (org-mode . org-appear-mode)
  :config
  (setq org-appear-autoemphasis t      ; :: */~_ emphasis markers
        org-appear-autolinks t         ; :: [[link][desc]] brackets + target
        org-appear-autosubmarkers t))  ; :: ^{} _{} sub/superscript markup

;; ──────────────────────────────────────────────────────
;; :: org-modern-indent -- block brackets under org-indent-mode
;; ──────────────────────────────────────────────────────
;; :: org-modern draws the #+begin_src/#+end_src bracket on the left fringe, but
;; :: positions it wrong once `org-indent-mode' shifts text right (Doom enables
;; :: org-indent by default). org-modern-indent recomputes the bracket against
;; :: the indented text so blocks stay framed correctly.
(use-package! org-modern-indent
  :hook (org-mode . org-modern-indent-mode))

;; ──────────────────────────────────────────────────────
;; :: Editing niceties -- snipe, vertico, xref, flycheck
;; ──────────────────────────────────────────────────────
;; :: evil-snipe: f/F/t/T jump on the current line first, then spill to the
;; :: visible window when the char isn't on the line.
(after! evil-snipe
  (setq evil-snipe-scope 'line
        evil-snipe-spillover-scope 'visible))

;; :: Vertico -- vim navigation in completion buffers.
;; :: C-j/C-k move while typing; ESC drops to normal mode for j/k/gg/G/p.
(after! vertico
  (map! :map vertico-map
        "C-j" #'vertico-next
        "C-k" #'vertico-previous)
  (map! :map vertico-map
        :i [escape] #'evil-normal-state)
  (map! :map vertico-map
        :n "j"  #'vertico-next
        :n "k"  #'vertico-previous
        :n "gg" #'vertico-first
        :n "G"  #'vertico-last
        :n "q"  #'abort-minibuffers
        :n "p"  (lambda () (interactive)
                  (let ((text (current-kill 0)))
                    (delete-minibuffer-contents)
                    (insert text)))))

;; :: xref -- jump directly when only one definition is found.
(after! xref
  (setq xref-auto-jump-to-first-definition t))

;; :: Flycheck -- don't self-disable on transient startup diagnostic bursts.
;; :: tsserver floods unresolved-symbol diagnostics during the first seconds of
;; :: indexing then clears them; the default threshold (400) would permanently
;; :: disable the checker. nil = no cap.
(after! flycheck
  (setq flycheck-checker-error-threshold nil))

;; ──────────────────────────────────────────────────────
;; :: Magit -- relative line numbers + vim motions
;; ──────────────────────────────────────────────────────
(after! magit
  (add-hook 'magit-mode-hook
            (lambda () (setq-local display-line-numbers 'relative)))
  ;; :: reclaim H/M/L for evil screen motions (M was Magit's remote menu; reach
  ;; :: it via the menu key ?).
  (map! :map magit-mode-map
        :n "H" #'evil-window-top
        :n "M" #'evil-window-middle
        :n "L" #'evil-window-bottom)
  ;; :: reclaim C-hjkl for pane navigation; Magit binds C-j/C-k to section
  ;; :: motion, which shadows the global window-nav.
  (map! :map magit-mode-map
        :nvieomr "C-h" #'evil-window-left
        :nvieomr "C-j" #'evil-window-down
        :nvieomr "C-k" #'evil-window-up
        :nvieomr "C-l" #'evil-window-right))

;; ──────────────────────────────────────────────────────
;; :: Workspaces -- show all workspaces in the modeline + restore session
;; ──────────────────────────────────────────────────────
(after! persp-mode
  (defun my/workspace-modeline-string ()
    (when (and (bound-and-true-p persp-mode)
               (fboundp '+workspace-list-names))
      (concat
       " "
       (mapconcat
        (lambda (name)
          (if (string= name (+workspace-current-name))
              (propertize (format "[%s]" name) 'face 'doom-modeline-buffer-major-mode)
            (propertize name 'face 'shadow)))
        (+workspace-list-names)
        " ")
       " ")))
  (add-to-list 'global-mode-string '(:eval (my/workspace-modeline-string)) t))

;; :: Session is restored manually -- `SPC q l' (doom/quickload-session) or the
;; :: dashboard "Reload last session" entry. Doom still auto-saves on quit; we
;; :: just don't auto-load on startup. Save/load named workspaces: SPC TAB s / l.

;; ──────────────────────────────────────────────────────
;; :: Shadow workspaces -- live preview while switching (SPC TAB .)
;; ──────────────────────────────────────────────────────
;; :: While the switcher's minibuffer is open, switch to whichever candidate is
;; :: highlighted so you see it live; keep navigating, RET confirms, C-g restores
;; :: the workspace you started in. Driven off a buffer-local `post-command-hook'
;; :: in the minibuffer that reads Vertico's current candidate.
;; :: Infinite-loop guard (the backlog's worry): preview goes through
;; :: `+workspace-switch', which is NON-interactive -- it can't spawn a nested
;; :: minibuffer -- and we skip redundant switches by remembering the last name
;; :: previewed. `save-selected-window' keeps focus in the minibuffer so the
;; :: candidate list stays open and navigable across switches.
(defvar my/ws-preview-origin nil
  ":: Workspace active before the switcher opened; restored on abort.")
(defvar my/ws-preview-last nil
  ":: Last workspace name previewed, to skip redundant switches.")

(defun my/ws-preview--update ()
  ":: Switch to the highlighted candidate when it names a real workspace."
  (when (and (fboundp 'vertico--candidate) (bound-and-true-p vertico--input))
    (let ((cand (ignore-errors (vertico--candidate))))
      (when (and cand
                 (not (string= cand my/ws-preview-last))
                 (member cand (+workspace-list-names)))
        (setq my/ws-preview-last cand)
        (save-selected-window
          (+workspace-switch cand))))))

(defun my/workspace-switch-preview ()
  ":: `+workspace/switch-to' with live preview: each candidate is shown as you
move; RET confirms, C-g restores the starting workspace."
  (interactive)
  (setq my/ws-preview-origin (+workspace-current-name)
        my/ws-preview-last   my/ws-preview-origin)
  (let (chosen)
    (condition-case nil
        (minibuffer-with-setup-hook
            (lambda () (add-hook 'post-command-hook #'my/ws-preview--update nil t))
          (setq chosen (completing-read "Switch to workspace: "
                                        (+workspace-list-names) nil t)))
      (quit nil))
    (+workspace-switch (or chosen my/ws-preview-origin))))

;; :: DISABLED for now -- `SPC TAB .' stays on Doom's default
;; :: `+workspace/switch-to'. Uncomment to re-enable the live-preview switcher.
;; (map! :leader
;;       (:prefix "TAB"
;;        :desc "Switch workspace (preview)" "." #'my/workspace-switch-preview))

;; ──────────────────────────────────────────────────────
;; :: Buffer switcher grouped by project (SPC ,)
;; ──────────────────────────────────────────────────────
;; :: Workflow: one workspace holds files from many projects (instead of one
;; :: workspace per project). Doom's default `SPC ,' groups the picker by
;; :: WORKSPACE, which is useless once everything lives in a single workspace.
;; :: This rebinds `SPC ,' to the same consult--multi machinery keyed on the
;; :: buffer's projectile root instead: one header section per project, all
;; :: sections visible at once, narrow-keys per project. Scoped to the current
;; :: workspace so the notes workspace stays separate. `SPC b B' is untouched
;; :: (still every buffer, ungrouped). Modelled on Doom's
;; :: `+vertico--workspace-generate-sources' (completion/vertico/autoload/workspaces.el).
(after! consult
  (defun my/buffer-project-root (buf)
    ":: Projectile root for BUF's `default-directory', or nil if none.
Result is cached per-directory by projectile, so this stays cheap even when
called once per buffer per source."
    (with-current-buffer buf
      (and (fboundp 'projectile-project-root)
           (projectile-project-root))))

  (defun my/vertico--project-buffer-sources ()
    ":: Build consult buffer sources for the current workspace, one per project.
Real projects come first (alphabetical by root); buffers with no project land
in a trailing \"other\" section."
    (let* ((workspace (+workspace-current))
           (key-range (append (cl-loop for i from ?1 to ?9 collect i)
                              (cl-loop for i from ?a to ?z collect i)
                              (cl-loop for i from ?A to ?Z collect i)))
           (roots '())
           (i 0))
      ;; :: Collect the distinct project roots present among this workspace's buffers.
      (dolist (buf (buffer-list))
        (when (+workspace-contains-buffer-p buf workspace)
          (let ((root (my/buffer-project-root buf)))
            (unless (member root roots)
              (push root roots)))))
      ;; :: Real roots alphabetical, nil ("other") sorted to the end.
      (setq roots (sort roots (lambda (a b)
                                (cond ((null a) nil)
                                      ((null b) t)
                                      (t (string< a b))))))
      (mapcar
       (lambda (root)
         (cl-incf i)
         (let ((name (if root
                         (file-name-nondirectory (directory-file-name root))
                       "other")))
           `(:name     ,name
             :narrow   ,(nth (1- i) key-range)
             :category buffer
             :state    ,#'consult--buffer-state
             :items    ,(lambda ()
                          (consult--buffer-query
                           :sort 'visibility
                           :as #'buffer-name
                           :predicate
                           (lambda (buf)
                             (and (+workspace-contains-buffer-p buf workspace)
                                  (equal root (my/buffer-project-root buf)))))))))
       roots)))

  (defun my/switch-buffer-by-project ()
    ":: Switch to a buffer in the current workspace, grouped by project.
Like `+vertico/switch-workspace-buffer' but the header sections are projects
rather than workspaces."
    (interactive)
    (when-let (buffer (consult--multi (my/vertico--project-buffer-sources)
                                      :require-match
                                      (confirm-nonexistent-file-or-buffer)
                                      :prompt (format "Switch to buffer by project (%s): "
                                                      (+workspace-current-name))
                                      :history 'consult--buffer-history
                                      :sort nil))
      (funcall consult--buffer-display (car buffer)))))

(map! :leader
      :desc "Switch buffer (by project)" "," #'my/switch-buffer-by-project)

;; ──────────────────────────────────────────────────────
;; :: Window management -- splits, nav, swap, resize
;; ──────────────────────────────────────────────────────
(map! :leader
      :desc "Split window vertically" "|" #'evil-window-vsplit
      :desc "Split window horizontally" "-" #'evil-window-split)

;; :: Ctrl+hjkl window navigation in every evil state (LazyVim style).
(map! :nvieomr "C-h" #'evil-window-left
      :nvieomr "C-j" #'evil-window-down
      :nvieomr "C-k" #'evil-window-up
      :nvieomr "C-l" #'evil-window-right)

;; ──────────────────────────────────────────────────────
;; :: Send any buffer to a bottom popup, and raise one back to a normal window.
;; :: Mirrors `+popup/buffer' but lets you pick the target buffer instead of only
;; :: the current one. Popups are `no-other-window', so C-hjkl skips them -- use
;; :: `my/popup-raise' (which focuses the popup first) to promote it to a real,
;; :: navigable window.
;; ──────────────────────────────────────────────────────
(defun my/buffer-to-popup (buffer)
  ":: display BUFFER (chosen interactively) in a Doom bottom popup window"
  (interactive (list (read-buffer "Buffer to popup: " nil t)))
  (let ((+popup--inhibit-transient t)
        +popup-remember-last)
    (+popup-buffer
     (get-buffer buffer)
     '((actions . (+popup-display-buffer-stacked-side-window-fn))))))

(defun my/popup-raise ()
  ":: raise the visible popup into a normal window -- focuses it first (via
   `+popup/other') so it works from your main window, not only inside the popup"
  (interactive)
  (unless (+popup-window-p (selected-window))
    (+popup/other))
  (if (+popup-window-p (selected-window))
      (+popup/raise (selected-window))
    (user-error "No popup window to raise")))

(map! :leader
      :desc "Buffer → popup" "b ~" #'my/buffer-to-popup
      :desc "Raise popup"    "b ^" #'my/popup-raise)

;; :: Auto copy-mode: suspends vterm's cursor-sync on normal state entry so Evil
;; :: scroll keys and mouse work freely. Back to insert re-attaches the live cursor.
(add-hook 'vterm-mode-hook
          (lambda ()
            (add-hook 'evil-normal-state-entry-hook
                      (lambda () (when (eq major-mode 'vterm-mode)
                                   (vterm-copy-mode 1)))
                      nil t)
            (add-hook 'evil-insert-state-entry-hook
                      (lambda () (when (and (eq major-mode 'vterm-mode)
                                            vterm-copy-mode)
                                   (vterm-copy-mode -1)))
                      nil t)))

;; :: Free up ESC inside vterm so it reaches the underlying TUI (e.g. Claude
;; :: Code) instead of dropping Evil into normal state. C-[ is byte-identical to
;; :: ESC so it passes through too. A tmux-style `C-a' leader (mirrors the prefix
;; :: in ~/.tmux.conf) takes over the old "pause" role: `C-a ['  enters normal
;; :: state -> vterm-copy-mode for scrollback (like tmux's `prefix ['), and
;; :: `C-a C-a' sends a literal C-a so beginning-of-line still works in the shell.
(defvar my/vterm-prefix-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "[")   #'evil-normal-state)
    (define-key map (kbd "C-a") (lambda () (interactive)
                                  (vterm-send-key "a" nil nil t)))
    map)
  ":: tmux-style `C-a' leader for vterm buffers.")

(map! :after vterm
      :map vterm-mode-map
      :i "<escape>" #'vterm-send-escape
      :i "C-a"      my/vterm-prefix-map)

;; :: `C-;' single-press toggle between normal (copy-mode) and insert. Emacs
;; :: swallows it in vterm-mode-map before it hits the pty, and no terminal can
;; :: encode C-; so it never clashes with Claude Code's own vim mode.
(map! :after vterm
      :map vterm-mode-map
      :i "C-;" #'evil-normal-state
      :n "C-;" #'evil-insert)

;; :: vterm captures raw keys in insert state, so re-bind C-hjkl in its map.
(map! :after vterm
      :map vterm-mode-map
      :nvieomr "C-h" #'evil-window-left
      :nvieomr "C-j" #'evil-window-down
      :nvieomr "C-k" #'evil-window-up
      :nvieomr "C-l" #'evil-window-right)

;; :: Directional pane resize (tmux-style Alt+hjkl, mirrors ~/.tmux.conf).
;; :: Buffer-aware: each key moves the shared divider in its own direction no
;; :: matter which pane is focused -- M-h/M-l move the vertical divider left/
;; :: right, M-j/M-k move the horizontal divider down/up. The naive "always
;; :: decrease/increase the current window" felt backwards in the right/bottom
;; :: pane (M-h shrank *you*, sliding the divider right). The fix: if there's a
;; :: neighbor in the key's direction, grow the current window (pushing the
;; :: divider that way); if we're already at that edge, shrink instead -- either
;; :: way the divider travels the same direction regardless of focus.
(defun my/resize-h (&optional delta)
  ":: Move the vertical divider left: grow if a left neighbor exists, else
shrink (DELTA columns, default 10)."
  (interactive)
  (let ((delta (or delta 10)))
    (if (window-in-direction 'left)
        (evil-window-increase-width delta)
      (evil-window-decrease-width delta))))

(defun my/resize-l (&optional delta)
  ":: Move the vertical divider right (DELTA columns, default 10)."
  (interactive)
  (let ((delta (or delta 10)))
    (if (window-in-direction 'right)
        (evil-window-increase-width delta)
      (evil-window-decrease-width delta))))

(defun my/resize-j (&optional delta)
  ":: Move the horizontal divider down (DELTA rows, default 5)."
  (interactive)
  (let ((delta (or delta 5)))
    (if (window-in-direction 'below)
        (evil-window-increase-height delta)
      (evil-window-decrease-height delta))))

(defun my/resize-k (&optional delta)
  ":: Move the horizontal divider up (DELTA rows, default 5)."
  (interactive)
  (let ((delta (or delta 5)))
    (if (window-in-direction 'above)
        (evil-window-increase-height delta)
      (evil-window-decrease-height delta))))

(map! :nvieomr "M-h" #'my/resize-h
      :nvieomr "M-l" #'my/resize-l
      :nvieomr "M-j" #'my/resize-j
      :nvieomr "M-k" #'my/resize-k)

(map! :after vterm
      :map vterm-mode-map
      :nvieomr "M-h" #'my/resize-h
      :nvieomr "M-l" #'my/resize-l
      :nvieomr "M-j" #'my/resize-j
      :nvieomr "M-k" #'my/resize-k)

;; :: Restore pane resize in markdown-mode (it grabs M-hjkl for heading promotion).
(after! markdown-mode
  (define-key markdown-mode-map (kbd "M-h") nil)
  (define-key markdown-mode-map (kbd "M-l") nil)
  (define-key markdown-mode-map (kbd "M-j") nil)
  (define-key markdown-mode-map (kbd "M-k") nil))

;; ──────────────────────────────────────────────────────
;; :: zoom -- auto-resize the focused window
;; ──────────────────────────────────────────────────────
;; :: `zoom-mode' is a global minor mode: while ON, every window-selection change
;; :: grows the selected window and shrinks the rest, rebalancing as focus moves
;; :: -- so with many vertical splits the pane you're in gets usable width and the
;; :: others tuck away. It's OFF by default (no `:hook'); `SPC w z' toggles it,
;; :: because while it's on your M-hjkl (`my/resize-*') hand-sizing gets reverted
;; :: on the next window switch. `zoom-size' as a (w . h) pair < 1.0 is read as a
;; :: fraction of the frame; 0.618 is the golden ratio.
;; ::
;; :: (This is the *continuous auto-resize* toggle -- distinct from `SPC d Z'
;; :: `doom/window-enlargen', which one-shot zooms the current buffer.)
(use-package! zoom
  :init
  (map! :leader :desc "Toggle auto-zoom (zoom-mode)" "w z" #'zoom-mode)
  :config
  (setq zoom-size '(0.618 . 0.618)
        ;; :: Never resize these -- the db table viewers render fixed-width,
        ;; :: column-aligned output (they keep `truncate-lines'), and the
        ;; :: minibuffer/echo area must stay put.
        zoom-ignored-major-modes '(my/sql-result-mode my/sql-colsel-mode)
        zoom-ignored-buffer-name-regexps '("^ \\*")
        ;; :: Don't zoom while a which-key/transient/minibuffer popup is up.
        zoom-ignore-predicates (list (lambda () (> (minibuffer-depth) 0)))))

;; ──────────────────────────────────────────────────────
;; :: New frame -- moved off `C-x 5 2' onto `SPC w W'
;; ──────────────────────────────────────────────────────
(map! :leader :desc "New frame" "w W" #'make-frame-command)
(global-set-key (kbd "C-x 5 2") nil)

(defun my/swap-window-forward ()
  "Swap current window buffer with the next window."
  (interactive)
  (let ((next (next-window)))
    (unless (eq next (selected-window))
      (window-swap-states (selected-window) next))))

(defun my/swap-window-backward ()
  "Swap current window buffer with the previous window."
  (interactive)
  (let ((prev (previous-window)))
    (unless (eq prev (selected-window))
      (window-swap-states (selected-window) prev))))

;; :: ace-window -- tmux `C-a q` style: flash a floating number on each window,
;; :: press it to jump, then the overlay vanishes.
(use-package! ace-window
  :config
  ;; :: Label windows with digits instead of the default home-row letters.
  (setq aw-keys '(?1 ?2 ?3 ?4 ?5 ?6 ?7 ?8 ?9)
        ;; :: Only label windows in the current frame.
        aw-scope 'frame)
  ;; :: Make the floating number big and centered so it reads at a glance.
  (setq aw-leading-char-style 'char)
  (custom-set-faces!
    '(aw-leading-char-face :height 5.0 :weight bold :foreground "#ff6c6b")))

(map! :leader
      :desc "Jump to window (ace)" "w SPC" #'ace-window)

;; :: Free C-u for Emacs's universal argument (Doom binds it to evil-scroll-up).
;; :: Use C-b for full-page scroll-up.
(map! :nvm "C-u" #'universal-argument)

;; ──────────────────────────────────────────────────────
;; :: Global keybindings
;; ──────────────────────────────────────────────────────
(map! "C-c t" #'+vterm/toggle)
(map! :n "K" #'my/smart-lookup)

(map! :leader
      :desc "Swap window forward" "]" #'my/swap-window-forward
      :desc "Swap window backward" "[" #'my/swap-window-backward
      :desc "Find file in project" "SPC" #'projectile-find-file
      :desc "Search project"       "/"   #'+default/search-project)

(map! :leader
      :prefix "o"
      :desc "Toggle terminal" "v" #'+vterm/toggle
      :desc "Toggle terminal (alt)" "T" #'+vterm/toggle
      :desc "Wrap in quote block" "q" #'my/org-wrap-quote
      :desc "Wrap in src block" "c" #'my/org-wrap-src)

(map! :leader
      :prefix "n"
      :desc "Reference project file" "l" #'my/reference-project-file
      :desc "Copy region as org link" "y" #'my/copy-region-as-org-link
      :desc "Find file in notes"     "d" #'my/find-file-in-notes
      :desc "Search notes"           "/" #'my/search-notes)

;; :: denote: reference notes + journal (see modules/denote.el)
(map! :leader
      :prefix "n"
      :desc "New/open denote note" "n" #'denote-open-or-create
      :desc "Find note (consult)"  "f" #'consult-denote-find
      :desc "Grep notes (consult)" "g" #'consult-denote-grep
      :desc "Journal (today)"      "j" #'denote-journal-new-or-existing-entry
      :desc "Insert link to note"  "i" #'denote-link
      :desc "Link or create note"  "I" #'denote-link-or-create)

(map! :leader
      :prefix "f"
      :desc "Copy buffer file name" "n" #'my/copy-buffer-file-name
      :desc "Copy buffer directory" "N" #'my/copy-buffer-directory)

(map! :map org-mode-map
      :localleader
      "il" #'link-file)

;; ──────────────────────────────────────────────────────
;; :: Load feature modules (cross-platform)
;; ──────────────────────────────────────────────────────
(load! "modules/org-agenda")
(load! "modules/denote")        ; :: reference notes + journal (denote)
(load! "modules/gitlab")
(load! "modules/dashboard")     ; :: after gitlab -- it references gitlab functions
(load! "modules/snippet")
(load! "modules/org-brain")     ; :: second-brain query interface
(load! "modules/schema")        ; :: API schema endpoint navigation

(map! :leader
      :prefix "n"
      :desc "Query second brain"   "q" #'org-brain-query
      :desc "Re-run last query"    "Q" #'org-brain-rerun
      :desc "Insert schema endpoint link" "e" #'my/schema-insert-endpoint-link)

;; ──────────────────────────────────────────────────────
;; :: Load modules
;; ──────────────────────────────────────────────────────
(load! "modules/finance")
(load! "modules/inventory")
(load! "modules/todo-agenda")
(load! "modules/uuid")          ; :: SPC i u -- insert a v4 UUID
(load! "modules/reminders")     ; :: SPC d r -- reminders.org + appt notifications
;; :: db modules: sql connections + templates, table browser, saved queries
(load! "modules/db")
(load! "modules/db-browser")
(load! "modules/db-saved")
(load! "modules/db-write")      ; :: edit/delete rows + transactions (after db-browser)
(load! "modules/web")
(load! "modules/claude")        ; :: , c -- ask Claude about visual selection
(load! "modules/hackernews")    ; :: SPC o h -- in-buffer Hacker News reader
(load! "modules/keybindings")   ; :: keep this last

;; :: Terminal cursor shape in `emacs -nw' (no-op in GUI on either OS).
(unless (display-graphic-p)
  (require 'evil-terminal-cursor-changer)
  (evil-terminal-cursor-changer-activate))
