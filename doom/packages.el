;; -*- no-byte-compile: t; -*-
;;; $DOOMDIR/packages.el

;; :: web-mode for .tsx/.jsx without tree-sitter (libtree-sitter 0.26 vs Emacs
;; :: 30.2 breaks the tsx grammar's predicate queries). See config.el.
(package! web-mode)

;; :: vtsls under lsp-mode -- wraps VS Code's TS engine; handles Vite solution-
;; :: style tsconfigs that the built-in ts-ls (typescript-language-server) gets
;; :: wrong. Registers at :priority -1, beating ts-ls (-2), so it's auto-chosen.
(package! lsp-vtsls :recipe (:host github :repo "sdvcrx/lsp-vtsls"))

;; :: tailwindcss-language-server client for lsp-mode. (Upstream lsp-mode merged
;; :: a built-in client on master, but Doom pins lsp-mode 9.0.1, which predates
;; :: it -- so the external package is still required here.) Run as an add-on so
;; :: it coexists with vtsls; see config.el.
(package! lsp-tailwindcss :recipe (:host github :repo "merrickluo/lsp-tailwindcss"))
;; To install a package with Doom you must declare them here and run 'doom sync'
;; on the command line, then restart Emacs for the changes to take effect.

;; To install SOME-PACKAGE from MELPA, ELPA or emacsmirror:
;; (package! some-package)

;; To install a package directly from a remote git repo, you must specify a
;; `:recipe'. You'll find documentation on what `:recipe' accepts here:
;; https://github.com/radian-software/straight.el#the-recipe-format
;; (package! another-package
;;   :recipe (:host github :repo "username/repo"))

;; If you'd like to disable a package included with Doom, you can do so here
;; with the `:disable' property:
;; (package! builtin-package :disable t)

;; Use `:pin' to specify a particular commit to install.
;; (package! builtin-package :pin "1a2b3c4d5e")

;; :: Calendar sync (CalDAV) for the :app calendar module.
(package! org-caldav)
;; :: Centered minibuffer posframe (config commented in config.el; kept available).
(package! vertico-posframe)

;; :: Terminal clipboard (OSC52) -- used on macOS in +macos.el; installed
;; :: everywhere but only activated there.
(package! clipetty)

;; :: Block/bar cursor shapes in `emacs -nw'.
(package! evil-terminal-cursor-changer)

;; :: ace-window -- transient floating window-number overlay (tmux `C-a q'
;; :: style jump-to-pane). Config + keybind in config.el.
(package! ace-window)

;; :: org-modern -- clean, modern org-mode styling (bullets, tags, blocks,
;; :: tables). Config in config.el.
(package! org-modern)

;; :: org-appear -- the editing half of org-modern: reveal emphasis markers,
;; :: links and sub/superscript markup only while point is inside them, so the
;; :: hidden glyphs come back exactly when you need to edit. Config in config.el.
(package! org-appear)

;; :: org-modern-indent -- restores org-modern's #+begin/#+end block brackets
;; :: under `org-indent-mode' (org-modern alone draws them wrong when indented).
;; :: Not on MELPA, so pull from GitHub. Config in config.el.
(package! org-modern-indent
  :recipe (:host github :repo "jdtsmith/org-modern-indent"))

;; :: org-super-agenda -- group agenda items into labelled sections (Today,
;; :: Overdue, by priority, ...) instead of one flat list. Config in
;; :: modules/org-agenda.el.
(package! org-super-agenda)

;; :: zoom -- auto-resize the focused window (grow it, shrink the rest) on every
;; :: window-selection change; rebalances when focus leaves. Config in config.el.
(package! zoom)

;; :: denote -- filename-as-metadata reference notes, decoupled from the agenda.
;; :: Config in modules/denote.el.
(package! denote)
(package! denote-journal)   ;; :: journaling split out of denote core since v4.0.0
(package! consult-denote)   ;; :: consult find + live grep over notes
