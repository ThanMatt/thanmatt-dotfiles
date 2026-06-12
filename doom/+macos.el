;;; +macos.el --- macOS-specific config -*- lexical-binding: t; -*-

;; :: Loaded from config.el when (featurep :system 'macos). Everything here is
;; :: Homebrew / NS (Cocoa) / lsp-mode specific and would be inert or wrong on
;; :: Linux.

;; ──────────────────────────────────────────────────────
;; :: Notes / org root (this machine)
;; ──────────────────────────────────────────────────────
(setq my/notes-dir (expand-file-name "~/notes/"))

;; ──────────────────────────────────────────────────────
;; :: Environment Variables from Shell (GUI Emacs)
;; ──────────────────────────────────────────────────────
;; :: GUI-launched Emacs on macOS doesn't inherit the Fish environment, so
;; :: import the vars the config reads (GitLab integration, project search
;; :: paths, schema file) before the `load!'s in config.el run.
(after! exec-path-from-shell
  (when (memq window-system '(mac ns x))
    (dolist (var '("GITLAB_URL"
                   "GITLAB_PROJECT_ID"
                   "GITLAB_PROJECT_NAME"
                   "GITLAB_ISSUES_DIR"
                   "PROJECT_SEARCH_PATHS"
                   "SCHEMA_FILE"))
      (add-to-list 'exec-path-from-shell-variables var))))

;; ──────────────────────────────────────────────────────
;; :: Shell -- Homebrew Fish for terminal emulators inside Emacs
;; ──────────────────────────────────────────────────────
(setq-default vterm-shell "/opt/homebrew/bin/fish")
(setq-default explicit-shell-file-name "/opt/homebrew/bin/fish")

;; ──────────────────────────────────────────────────────
;; :: Frame -- drop the OS titlebar
;; ──────────────────────────────────────────────────────
;; :: Truly borderless, like kitty/alacritty. On the emacs-plus NS build,
;; :: `undecorated-round' drops the titlebar while keeping macOS rounded
;; :: corners. The native fullscreen button goes with the bar, so fullscreen
;; :: via `SPC t F' (`toggle-frame-fullscreen'); `ns-appearance dark' keeps
;; :: menus/dialogs dark.
(add-to-list 'default-frame-alist '(undecorated-round . t))
(add-to-list 'default-frame-alist '(ns-transparent-titlebar . t))
(add-to-list 'default-frame-alist '(ns-appearance . dark)) ; or 'light

;; ──────────────────────────────────────────────────────
;; :: tree-sitter grammars (TSX engine toggle target)
;; ──────────────────────────────────────────────────────
;; :: Pin to v0.20.3 (grammar ABI 14) -- compatible with macOS Emacs's bundled
;; :: treesit. `master' tracks newer ABIs whose query predicates broke on the
;; :: Arch/Emacs-30.2 box, so never track it here. Grammars are already built in
;; :: Doom's cache; only reinstall via `my/tsx-install-grammars' if tsx-ts-mode
;; :: ever fails to load. (The `my/tsx-toggle-treesit' command lives in config.el.)
(setq treesit-language-source-alist
      '((typescript "https://github.com/tree-sitter/tree-sitter-typescript" "v0.20.3" "typescript/src")
        (tsx        "https://github.com/tree-sitter/tree-sitter-typescript" "v0.20.3" "tsx/src")))

(defun my/tsx-install-grammars ()
  ":: (Re)build the tsx + typescript grammars from the pinned sources above."
  (interactive)
  (dolist (lang '(tsx typescript))
    (treesit-install-language-grammar lang)))

;; ──────────────────────────────────────────────────────
;; :: lsp-mode backend (macOS uses :tools lsp without +eglot)
;; ──────────────────────────────────────────────────────
;; :: typescript-language-server registration with eglot, kept for an easy
;; :: revert to eglot. Inert while lsp-mode is the active backend.
(after! eglot
  (add-to-list 'eglot-server-programs
               '((typescript-mode typescript-tsx-mode typescript-ts-mode tsx-ts-mode)
                 "typescript-language-server" "--stdio")))

;; :: `typescript-tsx-mode' derives from web-mode, which lsp-mode maps to the
;; :: "html" language-id by default -- ts-ls would never attach. Pin the right
;; :: ids so ts-ls (and lsp-tailwindcss) activate.
(after! lsp-mode
  (add-to-list 'lsp-language-id-configuration '(typescript-tsx-mode . "typescriptreact"))
  (add-to-list 'lsp-language-id-configuration '(typescript-mode     . "typescript")))

;; :: Tailwind CSS LSP -- `add-on-mode t' layers Tailwind completion/hover on
;; :: top of ts-ls in the same buffer. Binary: tailwindcss-language-server.
;; :: Only activates in projects with a tailwind config (v3) or a v4 @import.
(use-package! lsp-tailwindcss
  :when (modulep! :tools lsp)
  :init
  (setq lsp-tailwindcss-add-on-mode t)
  :config
  (dolist (m '(typescript-tsx-mode web-mode typescript-mode))
    (add-to-list 'lsp-tailwindcss-major-modes m)))

;; ──────────────────────────────────────────────────────
;; :: Clipboard -- clipetty (OSC52) for terminal Emacs over tmux/SSH
;; ──────────────────────────────────────────────────────
(use-package! clipetty
  :hook (after-init . global-clipetty-mode))
