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
(defun my/reminders--notify (title body &optional urgency)
  ":: fire one desktop notification; returns the backend's exit code (0 = sent).
   URGENCY (\"critical\") makes mako/dunst hold the popup until it's dismissed --
   used for reminders missed while the machine was off."
  (cond
   ((eq system-type 'darwin)
    (call-process "osascript" nil nil nil "-e"
                  (format "display notification %S with title %S" body title)))
   ((executable-find "notify-send")               ;; :: Linux (mako/dunst)
    (apply #'call-process "notify-send" nil nil nil
           (append (list "-a" "Emacs")
                   (when urgency (list "-u" urgency))
                   (list title body))))
   (t (message "%s: %s" title body) 0)))

(defvar my/reminders-deliver-retry-interval 20
  ":: seconds between redelivery attempts (see `my/reminders--deliver')")

(defvar my/reminders-deliver-max-attempts 15
  ":: give up redelivering after this many tries -- ~5 min at the default interval")

(defun my/reminders--deliver (title body &optional urgency attempt)
  ":: notify, and keep retrying if it didn't land. At login Emacs can easily beat
   the notification daemon out of the gate; `notify-send' then just exits
   non-zero and the missed reminder would vanish silently. So retry until it
   sticks (or we run out of patience)."
  (let ((attempt (or attempt 1)))
    (unless (eq 0 (my/reminders--notify title body urgency))
      (when (< attempt my/reminders-deliver-max-attempts)
        (run-at-time my/reminders-deliver-retry-interval nil
                     #'my/reminders--deliver title body urgency (1+ attempt))))))

(defun my/appt-notify--one (min _new msg)
  ":: fire one desktop notification MIN (a string) minutes ahead of MSG"
  (my/reminders--notify (if (equal min "0")
                            "Reminder (now)"
                          (format "Reminder (in %s min)" min))
                        msg))

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

;; :: Declared, not defined: org.el owns this (it's the log `org-submit-bug-report'
;; :: attaches). This file is lexical-binding, so without the declaration the
;; :: `let' below would bind it lexically -- i.e. do nothing at all.
(defvar org--warnings)

(defun my/reminders-sync-appt ()
  ":: rebuild appt's schedule from the agenda (run on save + daily rollover)"
  (interactive)
  ;; :: This runs UNATTENDED -- idle timer at startup, midnight rollover, on save
  ;; :: -- and `org-agenda-to-appt' reaches `org-element-cache-map', which fires
  ;; :: `org-element--cache-warn' once PER ELEMENT while the cache is
  ;; :: inconsistent. That macro writes to `*Warnings*' AND pushes onto
  ;; :: `org--warnings', neither bounded, so one stale cache turned a background
  ;; :: sync into a daemon pinned at 100% CPU and growing ~9MB/s.
  ;; ::
  ;; :: Cap both sinks for the duration. `:error' as the LOG level is the one
  ;; :: that matters: `display-warning' tests `warning-minimum-log-level' before
  ;; :: it creates the buffer, so a `:warning' never allocates anything.
  ;; :: `org--warnings' is rebound so its pushes are discarded on exit. appt is
  ;; :: still rebuilt exactly as before -- a parse fault just can't take the
  ;; :: session with it now. The cache corruption ITSELF is addressed in
  ;; :: config.el, via `org-element-cache-persistent'.
  (let ((warning-minimum-log-level :error)
        (warning-minimum-level     :error)
        (org--warnings             nil))
    (org-agenda-to-appt t)))

;; :: prime appt shortly after startup, then refresh each midnight for the new day
;; :: (`my/reminders--startup' below also runs the missed-reminder catch-up)
(run-at-time "24:01" 86400 #'my/reminders-sync-appt)

;; ──────────────────────────────────────────────────────
;; :: Missed reminders -- catch up on anything that came due while we were off
;; ──────────────────────────────────────────────────────
;; :: `appt' only ever holds TODAY's list and drops entries whose time has already
;; :: passed, so a reminder scheduled for 09:00 is lost forever if the machine was
;; :: asleep/off at 09:00. Fix: persist a "last seen alive" heartbeat to disk, and
;; :: on startup notify for every unfinished reminder scheduled inside the gap
;; :: between that heartbeat and now. The window only ever moves forward, so
;; :: nothing is announced twice and nothing appt already handled is repeated.

(defvar my/reminders-state-file
  (expand-file-name "reminders-state"
                    (or (bound-and-true-p doom-data-dir) user-emacs-directory))
  ":: file holding the last time Emacs was known to be running
   (stamped by `my/reminders--heartbeat')")

(defvar my/reminders-missed-max-age-days 7
  ":: never announce a reminder missed longer ago than this -- coming back to the
   machine after a month away shouldn't dump a quarter's worth of notifications")

(defvar my/reminders-missed-max-notifications 5
  ":: above this many missed reminders, send one summary notification instead")

(defvar my/reminders-heartbeat-interval 60
  ":: seconds between heartbeat writes; also the worst-case overlap of the missed
   window, so keep it small enough that a just-fired appt isn't re-announced")

(defun my/reminders--last-seen ()
  ":: the persisted heartbeat, or nil the very first time we run"
  (when (file-exists-p my/reminders-state-file)
    (with-temp-buffer
      (insert-file-contents my/reminders-state-file)
      (ignore-errors (plist-get (read (current-buffer)) :last-seen)))))

(defun my/reminders--heartbeat ()
  ":: stamp \"Emacs was alive at this moment\" on disk"
  (with-temp-file my/reminders-state-file
    (let ((print-length nil) (print-level nil))
      (prin1 (list :last-seen (current-time)) (current-buffer)))))

(defun my/reminders--scheduled-between (from to)
  ":: (TIME . LABEL) for every not-DONE reminder scheduled in [FROM, TO), oldest
   first. Read in a throwaway buffer with mode hooks delayed so this never
   touches -- or is confused by -- a live reminders.org buffer."
  (when (file-exists-p my/reminders-file)
    (let (hits)
      (with-temp-buffer
        (insert-file-contents my/reminders-file)
        (delay-mode-hooks (org-mode))
        (org-map-entries
         (lambda ()
           (let ((sched (org-get-scheduled-time nil)))
             (when (and sched
                        (not (org-entry-is-done-p))
                        (time-less-p sched to)
                        (not (time-less-p sched from)))
               (push (cons sched
                           (concat (format-time-string "%a %H:%M" sched)
                                   " · " (org-get-heading t t t t)
                                   (when-let ((desc (org-entry-get nil "DESC")))
                                     (concat " -- " desc))))
                     hits))))))
      (sort hits (lambda (a b) (time-less-p (car a) (car b)))))))

(defun my/reminders-check-missed (&optional full)
  ":: announce reminders that came due while Emacs wasn't running. Called on
   startup; interactively with \\[universal-argument] it re-scans the whole
   `my/reminders-missed-max-age-days' window instead of just the gap, which is
   the easy way to see that notifications actually work."
  (interactive "P")
  (let* ((now    (current-time))
         (cutoff (time-subtract now (days-to-time my/reminders-missed-max-age-days)))
         (since  (if full cutoff (or (my/reminders--last-seen) now)))
         ;; :: clamp: a long absence shouldn't replay months of reminders
         (since  (if (time-less-p since cutoff) cutoff since))
         (missed (my/reminders--scheduled-between since now)))
    (my/reminders--heartbeat)           ;; :: window closes here -- never replayed
    (cond
     ((null missed)
      (when (called-interactively-p 'interactive) (message "No missed reminders")))
     ((> (length missed) my/reminders-missed-max-notifications)
      (my/reminders--deliver (format "%d missed reminders" (length missed))
                             (mapconcat #'cdr missed "\n")
                             "critical"))
     (t (dolist (m missed)
          (my/reminders--deliver "Missed reminder" (cdr m) "critical"))))))


;; :: Startup: rebuild appt's list for today, then replay whatever was missed
;; :: while we were off. Idle-delayed so notify-send meets a live session bus.
(defun my/reminders--startup ()
  (my/reminders-sync-appt)
  (my/reminders-check-missed))

(run-with-idle-timer 5 nil #'my/reminders--startup)
(run-with-timer my/reminders-heartbeat-interval my/reminders-heartbeat-interval
                #'my/reminders--heartbeat)
(add-hook 'kill-emacs-hook #'my/reminders--heartbeat)

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
      :desc "Set property"    "p" #'org-set-property
      :desc "Check missed"    "m" #'my/reminders-check-missed)

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
