;;; +linux.el --- Linux-specific config -*- lexical-binding: t; -*-

;; :: Loaded from config.el when not on macOS. Wayland clipboard, FHS shell
;; :: path, and xdg-open handlers -- none of which apply on macOS.

;; ──────────────────────────────────────────────────────
;; :: Notes / org root (this machine)
;; ──────────────────────────────────────────────────────
(setq my/notes-dir (expand-file-name "~/org-notes/"))

;; ──────────────────────────────────────────────────────
;; :: Font family (this machine)
;; ──────────────────────────────────────────────────────
;; :: FiraCode Nerd Font on Arch; Cascadia Code kept commented for an easy switch
;; :: to match macOS. Set here, not in config.el, because the platform `load!'
;; :: runs before config.el's appearance block.
(setq doom-font (font-spec :family "FiraCode Nerd Font" :size 12)
      doom-variable-pitch-font (font-spec :family "FiraCode Nerd Font" :size 14)
      doom-big-font (font-spec :family "FiraCode Nerd Font" :size 18))
;; (setq doom-font (font-spec :family "Cascadia Code" :size 12)
;;       doom-variable-pitch-font (font-spec :family "Cascadia Code" :size 14)
;;       doom-big-font (font-spec :family "Cascadia Code" :size 18))

;; ──────────────────────────────────────────────────────
;; :: Shell -- FHS Fish for terminal emulators inside Emacs
;; ──────────────────────────────────────────────────────
(setq vterm-shell "/usr/bin/fish")

;; ──────────────────────────────────────────────────────
;; :: Clipboard -- Wayland (wl-copy / wl-paste)
;; ──────────────────────────────────────────────────────
;; :: GUI Emacs under Wayland (sway) has no native clipboard bridge, so route
;; :: kill/yank through wl-clipboard. uuid.el's copy rides `kill-new', so it
;; :: lands on the Wayland clipboard too.
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

;; ──────────────────────────────────────────────────────
;; :: HEIC images -- hand off to the system viewer
;; ──────────────────────────────────────────────────────
(defun my/open-heic-externally ()
  "Open HEIC file at point with the external viewer."
  (interactive)
  (let ((file (buffer-file-name)))
    (when (and file (string-match-p "\\.heic\\'" file))
      (start-process "open-heic" nil "xdg-open" file))))

(add-to-list 'auto-mode-alist '("\\.heic\\'" . image-mode))
(add-hook 'image-mode-hook
          (lambda ()
            (when (string-match-p "\\.heic\\'" (or (buffer-file-name) ""))
              (my/open-heic-externally))))
