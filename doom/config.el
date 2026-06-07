;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; Place your private configuration here! Remember, you do not need to run 'doom
;; sync' after modifying this file!


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
