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
;; :: Font family (this machine)
;; ──────────────────────────────────────────────────────
;; :: Cascadia Code on macOS; FiraCode Nerd Font kept commented as a fallback
;; :: (uncomment if Cascadia is missing). Set here, not in config.el, because the
;; :: platform `load!' runs before config.el's appearance block.
;; (setq doom-font (font-spec :family "Cascadia Code" :size 12)
;;       doom-variable-pitch-font (font-spec :family "Cascadia Code" :size 14)
;;       doom-big-font (font-spec :family "Cascadia Code" :size 18))
(setq doom-font (font-spec :family "FiraCode Nerd Font" :size 12)
      doom-variable-pitch-font (font-spec :family "FiraCode Nerd Font" :size 14)
      doom-big-font (font-spec :family "FiraCode Nerd Font" :size 18))

;; ──────────────────────────────────────────────────────
;; :: Fonts -- force text presentation for symbol ranges
;; ──────────────────────────────────────────────────────
;; :: macOS CoreText picks Apple Color Emoji for any Unicode symbol it has an
;; :: emoji glyph for (checkmarks ✔, asterisks ✳, arrows, boxes, etc.) -- so
;; :: they render as color emoji in Emacs even though a terminal draws the plain
;; :: mono glyph. Fix by prepending FiraCode so text symbols resolve there first.
;; ::
;; :: Emacs 28+ classifies emoji-presentation chars under a SEPARATE `emoji'
;; :: script with its own fontset target, so prepending to `unicode' alone misses
;; :: them -- cover `symbol' and `emoji' too. Real emoji (U+1F000+) have no
;; :: FiraCode glyph and still fall through to Apple Color Emoji as normal.
;; ::
;; :: FiraCode itself has no glyphs for common dingbats (✔ U+2714, ✳ U+2733,
;; :: ✖ U+2716, ⚠ U+26A0) -- prepending it is a no-op for those, so they still
;; :: fall through to Apple Color Emoji. Menlo (macOS's system monospace font)
;; :: does have monochrome glyphs for them, so stack it in as a second choice
;; :: below FiraCode, ahead of the color-emoji fallback.
(dolist (script '(unicode symbol emoji))
  (set-fontset-font t script (font-spec :family "Menlo") nil 'prepend)
  (set-fontset-font t script (font-spec :family "FiraCode Nerd Font") nil 'prepend))

;; :: Script-level targeting above still leaves gaps -- `symbol'/`emoji' don't
;; :: cover every codepoint Apple Color Emoji is willing to draw. Menlo covers
;; :: most of Misc Symbols (149/256) and Dingbats (144/192) directly, so map
;; :: those two blocks explicitly too (this is what org-modern's replacement
;; :: stars like "✳" U+2733 live in). Remaining gaps are true
;; :: Emoji_Presentation=Yes characters with no monochrome glyph anywhere on
;; :: the system, and will still render as color emoji.
;; ::
;; :: Miscellaneous Technical (U+2300-23FF, e.g. "⏺" U+23FA) has almost no
;; :: Menlo coverage, but STIX Two Math -- bundled with macOS itself under
;; :: Supplemental fonts -- has full 256/256 coverage of that block and of
;; :: Misc Symbols, so stack it in below Menlo as a broader-coverage fallback.
(dolist (range '((#x2300 . #x23FF)    ; Miscellaneous Technical
                 (#x2600 . #x26FF)    ; Miscellaneous Symbols
                 (#x2700 . #x27BF))) ; Dingbats
  (set-fontset-font t range (font-spec :family "STIX Two Math") nil 'prepend)
  (set-fontset-font t range (font-spec :family "Menlo") nil 'prepend))

;; ──────────────────────────────────────────────────────
;; :: Clipboard -- clipetty (OSC52) for terminal Emacs over tmux/SSH
;; ──────────────────────────────────────────────────────
(use-package! clipetty
  :hook (after-init . global-clipetty-mode))
