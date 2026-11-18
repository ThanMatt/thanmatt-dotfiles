;;; modules/vault-sync.el -*- lexical-binding: t; -*-
;; :: Keep Emacs honest about vault files that change underneath it.
;; ::
;; :: The vaults live in a Syncthing folder that Orgzly on the phone also writes
;; :: to. Doom deliberately skips `global-auto-revert-mode' and only reverts a
;; :: buffer when it is shown or the frame regains focus -- which never happens
;; :: for the buffers the "notes" daemon keeps open in the background
;; :: (reminders.org, tasks.org, ... opened by `org-agenda-to-appt'). Those went
;; :: stale: a reminder added or ticked off on the phone never reached appt, and
;; :: the next `my/reminders-add' wrote over a file that had moved on.
;; ::
;; :: So: auto-revert every org buffer under `my/vaults-root', and whenever an
;; :: agenda file reverts, rebuild appt so phone edits arm (or disarm) desktop
;; :: notifications too. auto-revert never touches a buffer with unsaved edits,
;; :: so a half-typed change is never thrown away -- that case still gets the
;; :: usual "changed on disk" prompt.
;; ::
;; :: Reverts are driven by file-notify (inotify), not polling: once a buffer
;; :: has a watch, autorevert ignores the 5s poll for it. That is fine here --
;; :: Syncthing replaces a file by renaming a temp file over it, and the watch
;; :: (inotify watches the parent dir) catches that and re-arms itself. Checked
;; :: on Emacs 30.2 with repeated temp+rename replacements.

(require 'autorevert)
(declare-function org-agenda-file-p "org")

(setq auto-revert-verbose nil)          ;; :: no "Reverting buffer" echo per sync

(defun my/vault-sync--in-vault-p ()
  ":: non-nil if the current buffer visits a file anywhere under `my/vaults-root'
   (all vaults, not just the active one -- a vault switch shouldn't matter)"
  (and buffer-file-name
       (file-in-directory-p buffer-file-name my/vaults-root)))

(defun my/vault-sync--after-revert-h ()
  ":: an agenda file changed on disk (usually a phone edit) -> re-arm appt"
  (when (and (fboundp 'my/reminders-sync-appt)
             (org-agenda-file-p))
    (my/reminders-sync-appt)))

(defun my/vault-sync-enable-h ()
  ":: org-mode-hook: auto-revert vault files + re-sync appt after each revert"
  (when (my/vault-sync--in-vault-p)
    (auto-revert-mode 1)
    (add-hook 'after-revert-hook #'my/vault-sync--after-revert-h nil t)))

(add-hook 'org-mode-hook #'my/vault-sync-enable-h)

(provide 'vault-sync)
;;; vault-sync.el ends here
