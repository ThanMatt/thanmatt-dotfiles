;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; Place your private configuration here! Remember, you do not need to run 'doom
;; sync' after modifying this file!

;; :: GUI Emacs (launched from sway) never sources Fish, so asdf shims aren't on
;; :: PATH -- this breaks npx-based tools like apheleia formatters (exit 127).
;; :: Prepend the shims dir to both exec-path and the PATH env var.
(let ((asdf-shims (expand-file-name "~/.asdf/shims")))
  (when (file-directory-p asdf-shims)
    (add-to-list 'exec-path asdf-shims)
    (setenv "PATH" (concat asdf-shims path-separator (getenv "PATH")))))

;; ──────────────────────────────────────────────────────
;; :: TypeScript / TSX without tree-sitter
;; ──────────────────────────────────────────────────────
;; :: Doom's :lang javascript maps .tsx -> tsx-ts-mode (tree-sitter), but the
;; :: Arch libtree-sitter 0.26 / Emacs 30.2 predicate-query incompat makes that
;; :: grammar unreliable -- files intermittently fall back to a non-JSX mode, so
;; :: the LSP parses them as plain .ts and reports "cannot find name 'div'".
;; :: Route .tsx/.jsx to a web-mode-based major mode instead (no grammar dep).
;; :: A dedicated derived mode keeps it distinct from HTML web-mode, so eglot
;; :: only sends the "typescriptreact" language-id for actual TSX buffers.
(define-derived-mode typescript-tsx-mode web-mode "TSX"
  ":: web-mode-based major mode for .tsx/.jsx -- no tree-sitter.")

;; :: Win over Doom's tsx-ts-mode/typescript-ts-mode entries (add-to-list
;; :: prepends, and auto-mode-alist is searched in order).
(add-to-list 'auto-mode-alist '("\\.[tj]sx\\'" . typescript-tsx-mode))
(add-to-list 'auto-mode-alist '("\\.ts\\'"     . typescript-mode))

;; :: Use vtsls (not typescript-language-server): it wraps VS Code's TS engine
;; :: and correctly resolves Vite "solution-style" tsconfigs (root tsconfig.json
;; :: with `files: []` + `references`), which plain typescript-language-server
;; :: does not -- that fallback turns jsx off + implicit-any on and floods every
;; :: <div> with bogus diagnostics. Install: npm i -g @vtsls/language-server
;; :: The per-mode :language-id is what tells vtsls whether a buffer is TSX.
(after! eglot
  (add-to-list 'eglot-server-programs
               '(((typescript-tsx-mode :language-id "typescriptreact")
                  (typescript-mode     :language-id "typescript")
                  (js-mode             :language-id "javascript")
                  (js2-mode            :language-id "javascript"))
                 . ("vtsls" "--stdio"))))

;; :: Doom only attaches the LSP client to the modes its javascript module
;; :: manages; our web-mode-based TSX mode needs the hook added explicitly.
(add-hook 'typescript-tsx-mode-local-vars-hook #'lsp!)
(add-hook 'typescript-mode-local-vars-hook     #'lsp!)

;; ──────────────────────────────────────────────────────
;; :: TSX typing performance (web-mode + eglot)
;; ──────────────────────────────────────────────────────
;; :: In a .tsx buffer every keystroke triggers web-mode's after-change scan,
;; :: an eglot didChange, a corfu completion query and an eldoc hover. web-mode
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
;; :: the cost grows with how deeply nested the JSX at point is -- which is why a
;; :: big Dialog/Tabs tree lags while the flat JSX above it stays fast. web-mode
;; :: has no incremental parser (that's tree-sitter, which is broken here), so we
;; :: take fontification off the keystroke's critical path instead: the char is
;; :: inserted immediately and colors catch up ~50ms later when typing pauses.
(defun my/tsx-typing-perf ()
  ":: Buffer-local latency tweaks for deeply-nested JSX in web-mode TSX buffers."
  (setq-local jit-lock-defer-time 0.05      ; :: defer font-lock; don't run per-key
              jit-lock-stealth-time nil      ; :: no background full-buffer fontify
              web-mode-jsx-depth-faces nil)) ; :: skip per-depth JSX bg shading (costly)
(add-hook 'typescript-tsx-mode-hook #'my/tsx-typing-perf)

;; :: eglot logs every LSP JSON message into a hidden events buffer by default;
;; :: that's real overhead on each didChange (one per keystroke). Size 0 = off.
;; :: send-changes-idle-time batches edits so vtsls isn't notified mid-burst.
(after! eglot
  (setq eglot-events-buffer-config '(:size 0 :format full)
        eglot-sync-connect nil                  ; :: never block the UI on the server
        eglot-send-changes-idle-time 0.5))


;; Some functionality uses this to identify you, e.g. GPG configuration, email
;; clients, file templates and snippets. It is optional.
;; (setq user-full-name "John Doe"
;;       user-mail-address "john@doe.com")

;; Doom exposes five (optional) variables for controlling fonts in Doom:
;;
;; - `doom-font' -- the primary font to use
;; - `doom-variable-pitch-font' -- a non-monospace font (where applicable)
;; - `doom-big-font' -- used for `doom-big-font-mode'; use this for
;;   presentations or streaming.
;; - `doom-symbol-font' -- for symbols
;; - `doom-serif-font' -- for the `fixed-pitch-serif' face
;;
;; See 'C-h v doom-font' for documentation and more examples of what they
;; accept. For example:
;;
;;(setq doom-font (font-spec :family "Fira Code" :size 12 :weight 'semi-light)
;;      doom-variable-pitch-font (font-spec :family "Fira Sans" :size 13))
;;
;; If you or Emacs can't find your font, use 'M-x describe-font' to look them
;; up, `M-x eval-region' to execute elisp code, and 'M-x doom/reload-font' to
;; refresh your font settings. If Emacs still can't find your font, it likely
;; wasn't installed correctly. Font issues are rarely Doom issues!

;; There are two ways to load a theme. Both assume the theme is installed and
;; available. You can either set `doom-theme' or manually load a theme with the
;; `load-theme' function. This is the default:
(setq doom-gruvbox-dark-variant "medium")
(setq doom-theme 'doom-gruvbox)

(setq wl-copy-process nil)

(defun wl-copy (text)
  (setq wl-copy-process (make-process :name "wl-copy"
                                      :buffer nil
                                      :command '("wl-copy" "-f" "-n")
                                      :connection-type 'pipe
                                      :noquery t))
  (process-send-string wl-copy-process text)
  (process-send-eof wl-copy-process))

(defun wl-paste ()
  (if (and wl-copy-process (process-live-p wl-copy-process))
      nil
    (shell-command-to-string "wl-paste -n | tr -d \r")))

(setq interprogram-cut-function 'wl-copy)
(setq interprogram-paste-function 'wl-paste)



;; This determines the style of line numbers in effect. If set to `nil', line
;; numbers are disabled. For relative line numbers, set this to `relative'.
(setq display-line-numbers-type 'relative)

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/notes/")


;; Whenever you reconfigure a package, make sure to wrap your config in an
;; `after!' block, otherwise Doom's defaults may override your settings. E.g.
;;
;;   (after! PACKAGE
;;     (setq x y))
;;
;; The exceptions to this rule:
;;
;;   - Setting file/directory variables (like `org-directory')
;;   - Setting variables which explicitly tell you to set them before their
;;     package is loaded (see 'C-h v VARIABLE' to look up their documentation).
;;   - Setting doom variables (which start with 'doom-' or '+').
;;
;; Here are some additional functions/macros that will help you configure Doom.
;;
;; - `load!' for loading external *.el files relative to this one
;; - `use-package!' for configuring packages
;; - `after!' for running code after a package has loaded
;; - `add-load-path!' for adding directories to the `load-path', relative to
;;   this file. Emacs searches the `load-path' when you load packages with
;;   `require' or `use-package'.
;; - `map!' for binding new keys
;;
;; To get information about any of these functions/macros, move the cursor over
;; the highlighted symbol at press 'K' (non-evil users must press 'C-c c k').
;; This will open documentation for it, including demos of how they are used.
;; Alternatively, use `C-h o' to look up a symbol (functions, variables, faces,
;; etc).
;;
;; You can also try 'gd' (or 'C-c c d') to jump to their definition and see how
;; they are implemented.
;; Use bash for internal Emacs processes
(setq shell-file-name (executable-find "bash"))

;; But keep Fish for terminal emulators within Emacs
; :: For mac
; (setq-default vterm-shell "/opt/homebrew/bin/fish")
; (setq-default explicit-shell-file-name "/opt/homebrew/bin/fish")

(setq vterm-shell "/usr/bin/fish")

;; Set the default font
(setq doom-font (font-spec :family "FiraCode Nerd Font" :size 12)
      doom-variable-pitch-font (font-spec :family "FiraCode Nerd Font" :size 14))

;; Optional: Set bigger font for headings in org-mode
(setq doom-big-font (font-spec :family "FiraCode Nerd Font" :size 18))

(defun my/create-project (project-name)
  "Create a new project structure with template files."
  (interactive "sProject name: ")
  (let ((project-dir (expand-file-name 
                      (concat "~/notes/projects/" project-name))))
    ;; Create directory
    (make-directory project-dir t)
    ;; Create project.org with template
    (with-temp-file (concat project-dir "/project.org")
      (insert (format "#+TITLE: %s\n#+AUTHOR: Your Name\n#+DATE: %s\n\n* Overview\n\n* Goals\n- [ ] \n\n* Tasks\n** TODO \n\n* Resources\n\n* Notes\n"
                      project-name 
                      (format-time-string "%Y-%m-%d"))))
    ;; Open the new project file
    (find-file (concat project-dir "/project.org"))))

(setq org-export-show-temporary-export-buffer nil)
(defun my/org-export-html-open ()
  (interactive)
  (org-html-export-to-html)
  (browse-url (concat "file://" (expand-file-name (org-export-output-file-name ".html")))))
(global-set-key (kbd "C-c e h") #'my/org-export-html-open)


(org-babel-do-load-languages
 'org-babel-load-languages
 '((emacs-lisp . t)
   (python     . t)
   (shell      . t)
   (js         . t)))   ;; <- this enables JavaScript


(setq +doom-dashboard-ascii-banner-fn #'my/simple-banner)

(defun my/simple-banner ()
  '("                                    "
    "    Welcome to My Emacs Setup!     "
    "                                    "
    "         Ready to code...           "
    "                                    "))

;; :: Dashboard helper function for knowledgebase
(defun my/open-knowledgebase ()
  "Open the knowledgebase directory."
  (interactive)
  (dired "~/org-notes"))

;; :: Custom dashboard menu
(setq +doom-dashboard-menu-sections
      '(("Open Inventory"
         :icon (nerd-icons-octicon "nf-oct-package" :face 'doom-dashboard-menu-title)
         :action inventory/open-or-create)
        ("Current Financials"
         :icon (nerd-icons-octicon "nf-oct-graph" :face 'doom-dashboard-menu-title)
         :action finance/create-expense-tracker)
        ("Knowledgebase"
         :icon (nerd-icons-octicon "nf-oct-book" :face 'doom-dashboard-menu-title)
         :action my/open-knowledgebase)
        ("Open project"
         :icon (nerd-icons-octicon "nf-oct-briefcase" :face 'doom-dashboard-menu-title)
         :action projectile-switch-project)
        ("Recently opened files"
         :icon (nerd-icons-octicon "nf-oct-file" :face 'doom-dashboard-menu-title)
         :action recentf-open-files)
        ("Open org-agenda"
         :icon (nerd-icons-octicon "nf-oct-calendar" :face 'doom-dashboard-menu-title)
         :action org-agenda)))

; (set-frame-parameter nil 'internal-border-width 0)
;; Remove title bar (gives you more screen space)
; (add-to-list 'default-frame-alist '(undecorated . t))

; ;; Optional: Also remove the menu bar if you want
(menu-bar-mode -1)
;;
;; This gives you a minimal title bar
(add-to-list 'default-frame-alist '(ns-transparent-titlebar . t))
(add-to-list 'default-frame-alist '(ns-appearance . dark)) ; or 'light

(setq org-image-actual-width '(400))

(setq org-agenda-files '("~/notes/notes.org"
                         "~/notes/projects/"))

;; Toggle vterm in a popup window
(map! "C-c t" #'+vterm/toggle)

;; :: Keep vterm buffers (and their processes) alive when the window closes.
;; :: Doom's default rule uses :ttl 0, which KILLS the buffer the instant the
;; :: popup is dismissed (`:q`, q, escape) — that SIGHUPs any running server.
;; :: :ttl nil makes closing merely bury it; `C-c t' brings it back, server
;; :: still running. To actually stop it: `exit' in the shell, or kill-buffer.
(set-popup-rule! "^\\*vterm" :size 0.30 :vslot -4 :select t :quit nil :ttl nil)

;; Window splitting keybindings (LazyVim style)
(map! :leader
      :desc "Split window vertically" "|" #'evil-window-vsplit
      :desc "Split window horizontally" "-" #'evil-window-split)

;; Window navigation (LazyVim style with Ctrl+hjkl)
;; :: :nvieomr binds in every evil state so navigation works regardless of mode
;; :: (normal, visual, insert, emacs, operator, motion, replace).
(map! :nvieomr "C-h" #'evil-window-left
      :nvieomr "C-j" #'evil-window-down
      :nvieomr "C-k" #'evil-window-up
      :nvieomr "C-l" #'evil-window-right)

;; :: vterm (Claude Code, project terminals) captures raw keys in insert state,
;; :: so re-bind C-hjkl directly in its map to keep pane navigation working.
(map! :after vterm
      :map vterm-mode-map
      :nvieomr "C-h" #'evil-window-left
      :nvieomr "C-j" #'evil-window-down
      :nvieomr "C-k" #'evil-window-up
      :nvieomr "C-l" #'evil-window-right)

;; :: evil-snipe: let f/F/t/T spill past the current line.
;; :: Primary scope stays the line (so same-line jumps win first), but when the
;; :: character isn't on the current line, the search expands to the visible
;; :: window and jumps there instead of failing. Swap 'visible for 'buffer to
;; :: also reach off-screen lines.
(after! evil-snipe
  (setq evil-snipe-scope 'line
        evil-snipe-spillover-scope 'visible))

;; :: Free C-u for Emacs's universal argument (Doom binds it to evil-scroll-up).
;; :: Lets `C-u M-x ...' work. Trade-off: lose vim half-page scroll-up on C-u —
;; :: use C-b (full page) or remap it below if you miss it.
(map! :nvm "C-u" #'universal-argument)

;; :: Directional pane resize (tmux-style Alt+hjkl, mirrors ~/.tmux.conf)
;; :: h/l = width (10 cols), j/k = height (5 rows) — same steps as tmux.
;; :: :nvieomr binds in every evil state so resizing works regardless of mode.
(map! :nvieomr "M-h" (cmd! (evil-window-decrease-width 10))
      :nvieomr "M-l" (cmd! (evil-window-increase-width 10))
      :nvieomr "M-j" (cmd! (evil-window-increase-height 5))
      :nvieomr "M-k" (cmd! (evil-window-decrease-height 5)))

;; :: vterm captures raw keys in insert state, so re-bind the resize keys
;; :: directly in its map to keep pane resizing working there too.
(map! :after vterm
      :map vterm-mode-map
      :nvieomr "M-h" (cmd! (evil-window-decrease-width 10))
      :nvieomr "M-l" (cmd! (evil-window-increase-width 10))
      :nvieomr "M-j" (cmd! (evil-window-increase-height 5))
      :nvieomr "M-k" (cmd! (evil-window-decrease-height 5)))

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

;; :: Keep the old binding working and add a top-level one
(defalias '+org/insert-file-link #'link-file)

(map! :map org-mode-map
      :localleader
      "il" #'link-file)

;; :: Load finance module
(load! "modules/finance")

;; :: Load inventory module
(load! "modules/inventory")

;; :: Load todo-agenda module
(load! "modules/todo-agenda")

;; :: Open HEIC files with external viewer
(defun my/open-heic-externally ()
  "Open HEIC file at point with external viewer."
  (interactive)
  (let ((file (buffer-file-name)))
    (when (and file (string-match-p "\\.heic\\'" file))
      (start-process "open-heic" nil "xdg-open" file))))

;; Automatically use external viewer for HEIC files
(add-to-list 'auto-mode-alist '("\\.heic\\'" . image-mode))
(add-hook 'image-mode-hook
          (lambda ()
            (when (string-match-p "\\.heic\\'" (or (buffer-file-name) ""))
              (my/open-heic-externally))))


;; ──────────────────────────────────────────────────────
;; :: Flycheck — don't self-disable on transient startup bursts
;; ──────────────────────────────────────────────────────
;; :: eglot/tsserver floods unresolved-symbol diagnostics during the first few
;; :: seconds of project indexing, then clears them. The default threshold (400)
;; :: trips on that burst and permanently disables the checker for the buffer.
;; :: nil = no cap; set a number (e.g. 2000) instead if you want a ceiling.
(after! flycheck
  (setq flycheck-checker-error-threshold nil))

;; ──────────────────────────────────────────────────────
;; :: Magit — relative line numbers + vim H/M/L navigation
;; ──────────────────────────────────────────────────────
(after! magit
  ;; :: relative line numbers in Magit buffers (off by default there)
  (add-hook 'magit-mode-hook
            (lambda () (setq-local display-line-numbers 'relative)))
  ;; :: reclaim H/M/L for evil screen motions. Overrides Magit's own bindings
  ;; :: on these keys (notably M = remote menu); reach those via the menu (?).
  (map! :map magit-mode-map
        :n "H" #'evil-window-top
        :n "M" #'evil-window-middle
        :n "L" #'evil-window-bottom)
  ;; :: reclaim C-hjkl for pane navigation. Magit binds C-j/C-k to
  ;; :: magit-section-forward/backward ("No next section"), which shadows the
  ;; :: global window-nav, so re-bind them here where Magit's map wins.
  (map! :map magit-mode-map
        :nvieomr "C-h" #'evil-window-left
        :nvieomr "C-j" #'evil-window-down
        :nvieomr "C-k" #'evil-window-up
        :nvieomr "C-l" #'evil-window-right))

;; ──────────────────────────────────────────────────────
;; :: Workspaces — auto-restore last session on startup
;; ──────────────────────────────────────────────────────
;; :: Reloads whatever `doom/quicksave-session' last wrote (Doom auto-saves
;; :: the session on a normal quit via `SPC q q'). Save/load named workspaces
;; :: with `SPC TAB s' / `SPC TAB l'; full session via M-x doom/quicksave-session.
(add-hook 'window-setup-hook #'doom/quickload-session)

(load! "modules/web")
(load! "modules/keybindings") ; :: keep this last
