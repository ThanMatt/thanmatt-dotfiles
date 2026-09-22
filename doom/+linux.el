;;; +linux.el --- Linux-specific config -*- lexical-binding: t; -*-

;; :: Loaded from config.el when not on macOS. Wayland clipboard, FHS shell
;; :: path, and xdg-open handlers -- none of which apply on macOS.

;; ──────────────────────────────────────────────────────
;; :: Notes / org root (this machine) -- the container holding the vault dirs.
;; :: modules/vault.el derives `my/notes-dir' (the active vault) from this.
;; ──────────────────────────────────────────────────────
(setq my/vaults-root (expand-file-name "~/org-notes/"))

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
;; :: GPG passphrase prompts -- in-Emacs, no external pinentry
;; ──────────────────────────────────────────────────────
;; :: Same fix as +macos.el, different cause. Arch's /usr/bin/pinentry is a
;; :: wrapper that picks a backend from the environment; under Hyprland it lands
;; :: on pinentry-gnome3, which needs gcr's prompter on the session bus. When
;; :: that isn't reachable it silently degrades to pinentry-curses -- and GUI
;; :: Emacs has no controlling tty, so curses dies with "Inappropriate ioctl for
;; :: device" and ~/.authinfo.gpg never decrypts (breaking modules/db.el and
;; :: modules/db-browser.el, which read their creds from it).
;; ::
;; :: Loopback takes the external pinentry out of the loop entirely: Emacs reads
;; :: the passphrase in the minibuffer and hands it to gpg directly, so the db
;; :: browser no longer depends on the desktop's prompter being alive.
(setq epg-pinentry-mode 'loopback)

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

;; ──────────────────────────────────────────────────────
;; :: Sway workspace passthrough -- Ctrl+Super+h/l walks Doom workspaces
;; ──────────────────────────────────────────────────────
;; :: Sway owns Ctrl+Super+h/l and runs sway/scripts/ws-passthrough.sh, which
;; :: calls this over emacsclient when an Emacs window is focused. Returning
;; :: `pass' at either end of the workspace list is what makes sway and Doom
;; :: workspaces one continuous strip: the next press past the last Doom
;; :: workspace moves sway instead, so Emacs can never trap you.
;; ::
;; :: PID is the focused sway window's process. Anything that isn't THIS Emacs
;; :: (e.g. the "notes" daemon's floating frame) is passed straight back.
(defun my/sway-workspace-passthrough (dir pid)
  ":: Step the focused frame's Doom workspace in DIR (`prev' or `next').
Return `handled', or `pass' to let sway switch its own workspace instead."
  (if (not (and (eql pid (emacs-pid)) (bound-and-true-p persp-mode)))
      'pass
    (let ((frame (or (seq-find (lambda (f) (and (not (frame-parent f))
                                                (eq (frame-focus-state f) t)))
                               (frame-list))
                     (selected-frame))))
      (with-selected-frame frame
        (let* ((names (+workspace-list-names))
               (i (cl-position (+workspace-current-name) names :test #'equal))
               (j (and i (if (eq dir 'next) (1+ i) (1- i)))))
          (if (and j (>= j 0) (< j (length names)))
              (progn (+workspace/switch-to j) 'handled)
            'pass))))))
