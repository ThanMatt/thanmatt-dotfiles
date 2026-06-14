;;; modules/reminders.el -*- lexical-binding: t; -*-
;; :: A single reminders.org file of TODO headings, each with a SCHEDULED time.
;; :: Desktop notifications come from the built-in `appt' (fed by `org-agenda-to-appt'),
;; :: so there's almost no custom machinery -- org does the storage, sorting, and
;; :: scheduling; this module just opens the file and wires a few in-buffer keys.
;; ::
;; :: Shape (see `my/reminders-insert'):
;; ::   * TODO Renew passport
;; ::     SCHEDULED: <2026-07-01 09:00>
;; ::     :PROPERTIES:
;; ::     :DESC: bring old passport + 2 photos
;; ::     :END:
;; ::   ** TODO Book appointment      <- subtasks are child headings
;; ::   ** TODO Prepare documents

(require 'cl-lib)
(require 'appt)

(defvar my/reminders-file (expand-file-name "reminders.org" my/notes-dir)
  ":: the one file all reminders live in")

(defvar my/reminders-warn-minutes 10
  ":: how many minutes before a reminder's time to fire the desktop notification")

;; ──────────────────────────────────────────────────────
;; :: Desktop notification -- cross-platform, replaces appt's Emacs popup
;; ──────────────────────────────────────────────────────
(defun my/appt-notify--one (min _new msg)
  ":: fire one desktop notification MIN (a string) minutes ahead of MSG"
  (let ((title (if (equal min "0")
                   "Reminder (now)"
                 (format "Reminder (in %s min)" min))))
    (cond
     ((eq system-type 'darwin)
      (call-process "osascript" nil nil nil "-e"
                    (format "display notification %S with title %S" msg title)))
     ((executable-find "notify-send")              ;; :: Linux (mako/dunst)
      (call-process "notify-send" nil nil nil "-a" "Emacs" title msg))
     (t (message "%s: %s" title msg)))))

(defun my/appt-notify (min-to-app new-time msg)
  ":: appt display hook. appt hands all three args as parallel lists when several
   reminders fire at once, or as scalars for a single one -- handle both."
  (if (listp min-to-app)
      (cl-mapc #'my/appt-notify--one min-to-app new-time msg)
    (my/appt-notify--one min-to-app new-time msg)))

(setq appt-message-warning-time my/reminders-warn-minutes
      appt-display-interval     my/reminders-warn-minutes  ;; :: nag once, not every few min
      appt-display-mode-line    nil
      appt-display-format       'window
      appt-disp-window-function #'my/appt-notify
      appt-delete-window-function #'ignore)             ;; :: nothing to tear down

(appt-activate 1)

;; :: keep reminders.org in the agenda so `org-agenda-to-appt' can see its times
(after! org
  (add-to-list 'org-agenda-files my/reminders-file))

(defun my/reminders-sync-appt ()
  ":: rebuild appt's schedule from the agenda (run on save + daily rollover)"
  (interactive)
  (org-agenda-to-appt t))

;; :: prime appt shortly after startup, then refresh each midnight for the new day
(run-with-idle-timer 5 nil #'my/reminders-sync-appt)
(run-at-time "24:01" 86400 #'my/reminders-sync-appt)

;; ──────────────────────────────────────────────────────
;; :: In-buffer commands
;; ──────────────────────────────────────────────────────
(defun my/reminders-toggle ()
  ":: flip the reminder at point between TODO and DONE (bound to RET)"
  (interactive)
  (org-todo (if (org-entry-is-done-p) "TODO" "DONE")))

(defun my/reminders-insert ()
  ":: append a fresh reminder heading at the end and drop into insert state to
   type its title. Set the date with `, d', extra fields with `, p'."
  (interactive)
  (goto-char (point-max))
  (skip-chars-backward "\n")
  (delete-region (point) (point-max))   ;; :: trim trailing blank lines first
  (insert "\n\n* TODO ")
  (when (fboundp 'evil-insert-state) (evil-insert-state)))

(defun my/reminders-sort ()
  ":: re-sort all top-level reminders by their scheduled time (manual, on demand)"
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (org-sort-entries nil ?s))          ;; :: ?s = by SCHEDULED timestamp, ascending
  (message "Reminders sorted by date"))

;; ──────────────────────────────────────────────────────
;; :: Minor mode -- carries the buffer-local keys + appt-on-save hook
;; ──────────────────────────────────────────────────────
(defvar my/reminders-mode-map (make-sparse-keymap)
  ":: keymap active only in the reminders buffer")

(define-minor-mode my/reminders-mode
  ":: lightweight layer over org-mode for the reminders.org buffer"
  :lighter " Rem"
  :keymap my/reminders-mode-map
  (when my/reminders-mode
    ;; :: refresh notifications whenever the file is saved
    (add-hook 'after-save-hook #'my/reminders-sync-appt nil t)))

(map! :map my/reminders-mode-map
      :n "RET"    #'my/reminders-toggle
      :n [return] #'my/reminders-toggle
      :localleader
      :desc "Insert reminder" "i" #'my/reminders-insert
      :desc "Re-sort by date" "s" #'my/reminders-sort
      :desc "Toggle done"     "t" #'my/reminders-toggle
      :desc "Set/change date" "d" #'org-schedule
      :desc "Set property"    "p" #'org-set-property)

(defun my/reminders ()
  ":: open (or create) reminders.org with the reminder keys live"
  (interactive)
  (let ((new (not (file-exists-p my/reminders-file))))
    (find-file my/reminders-file)
    (when new
      (insert "#+TITLE: Reminders\n#+STARTUP: showall\n\n")
      (save-buffer))
    (my/reminders-mode 1)))

;; :: also enable the mode if reminders.org is opened any other way (SPC ,, recentf…)
(add-hook 'find-file-hook
          (lambda ()
            (when (and buffer-file-name
                       (file-equal-p buffer-file-name my/reminders-file))
              (my/reminders-mode 1))))

(provide 'reminders)
;;; reminders.el ends here
