;;; modules/redis-saved.el -*- lexical-binding: t; -*-

;; :: Save Redis commands and views to a persisted store and retrieve them with
;; :: a dimmed inline preview. Mirrors db-saved.el; loads AFTER redis.el and
;; :: redis-browser.el (see config.el).
;; ::
;; :: Three kinds are stored, so a saved entry reopens as the SAME kind of view
;; :: it was saved from rather than degrading to raw text:
;; ::   raw   :lines    -- a scratch selection or a replies view
;; ::   keys  :pattern :type :limit :sort-col :sort-desc
;; ::   key   :key

(require 'cl-lib)

(defvar my/redis-saved-file
  (expand-file-name "redis-saved.el"
                    (or (bound-and-true-p doom-data-dir) user-emacs-directory))
  ":: File saved commands persist to (one alist sexp), per-machine.")

(defvar my/redis-saved-commands nil
  ":: Alist NAME -> plist (:conn :db :kind :saved ...). Loaded lazily.")

(defvar my/redis--saved-loaded nil)

(defun my/redis--saved-load ()
  (unless my/redis--saved-loaded
    (when (file-exists-p my/redis-saved-file)
      (with-temp-buffer
        (insert-file-contents my/redis-saved-file)
        (setq my/redis-saved-commands (ignore-errors (read (current-buffer))))))
    (setq my/redis--saved-loaded t)))

(defun my/redis--saved-persist ()
  (with-temp-file my/redis-saved-file
    (let ((print-length nil) (print-level nil))
      (prin1 my/redis-saved-commands (current-buffer)))))

;; ──────────────────────────────────────────────────────
;; :: Capture the current context
;; ──────────────────────────────────────────────────────

(defun my/redis--current-state ()
  ":: Plist describing what the current buffer would reopen as.
   The connection is stored by NAME, not as the plist, so a saved entry survives
   editing the wallet (host moved, port changed) and still resolves."
  (cond
   ;; :: an explicit selection in the scratch pad wins over everything
   ((and (derived-mode-p 'my/redis-cmd-mode) (use-region-p))
    (list :kind 'raw :lines (my/redis--scratch-lines nil)))
   ((derived-mode-p 'my/redis-cmd-mode)
    (list :kind 'raw :lines (my/redis--scratch-lines t)))
   ((and (derived-mode-p 'my/redis-result-mode) (eq my/redis--view 'keys))
    (list :kind 'keys :pattern my/redis--pattern :type my/redis--type
          :limit my/redis--limit :sort-col my/redis--sort-col
          :sort-desc my/redis--sort-desc))
   ((and (derived-mode-p 'my/redis-result-mode) (eq my/redis--view 'key))
    (list :kind 'key :key my/redis--key))
   ((and (derived-mode-p 'my/redis-result-mode) (eq my/redis--view 'replies))
    (list :kind 'raw :lines my/redis--lines))
   (t (list :kind 'raw :lines (list (read-string "Command: "))))))

(defun my/redis--current-conn ()
  (or my/redis--conn (my/redis--read-conn "Connection: ")))

(defun my/redis--saved-preview (e)
  ":: One-line summary of a saved entry, for the picker annotation."
  (pcase (plist-get e :kind)
    ('raw  (string-join (plist-get e :lines) " ; "))
    ('keys (format "keys %s%s" (or (plist-get e :pattern) "*")
                   (if (plist-get e :type) (format " type %s" (plist-get e :type)) "")))
    ('key  (format "key %s" (plist-get e :key)))
    (_ "")))

(defun my/redis--saved-annotation (name)
  (let* ((e (alist-get name my/redis-saved-commands nil nil #'equal))
         (p (replace-regexp-in-string "[ \t\n\r]+" " " (my/redis--saved-preview e))))
    (concat (propertize (format "  [%s db%s] " (or (plist-get e :conn) "?")
                                (or (plist-get e :db) 0))
                        'face 'font-lock-keyword-face)
            (propertize (truncate-string-to-width p 80 nil nil "…") 'face 'shadow))))

(defun my/redis--saved-pick (prompt)
  (my/redis--saved-load)
  (unless my/redis-saved-commands (user-error "No saved Redis commands yet"))
  (let ((completion-extra-properties
         (list :annotation-function #'my/redis--saved-annotation)))
    (completing-read prompt (mapcar #'car my/redis-saved-commands) nil t)))

;; ──────────────────────────────────────────────────────
;; :: Commands
;; ──────────────────────────────────────────────────────

(defun my/redis-save-command ()
  ":: Save the current command / view (SPC d R w, or , s / , w in a buffer).
   Pick an existing name to overwrite it, or type a new one."
  (interactive)
  (my/redis--saved-load)
  (let* ((state (my/redis--current-state))
         (conn  (my/redis--current-conn))
         (db    (or my/redis--db (plist-get conn :db) 0))
         (default (format-time-string "%Y-%m-%d %H:%M:%S"))
         (completion-extra-properties
          (list :annotation-function #'my/redis--saved-annotation))
         (name (let ((n (completing-read
                         (format "Save as (default %s): " default)
                         (mapcar #'car my/redis-saved-commands))))
                 (if (string-empty-p n) default n))))
    ;; :: saved names show up in the completion list, so picking one by accident
    ;; :: is easy -- guard the overwrite (same as my/sql-save-query)
    (when (and (assoc name my/redis-saved-commands #'equal)
               (not (y-or-n-p (format "Command %S exists -- overwrite? " name))))
      (user-error "Aborted"))
    (setf (alist-get name my/redis-saved-commands nil nil #'equal)
          (append (list :conn (plist-get conn :name) :db db
                        :saved (format-time-string "%Y-%m-%d %H:%M:%S"))
                  state))
    (my/redis--saved-persist)
    (message "Saved %S (%s db%s) [%s]" name (plist-get conn :name) db
             (plist-get state :kind))))

(defun my/redis-run-saved (&optional arg)
  ":: Run a saved command / reopen a saved view (SPC d R q).
   With C-u, run it against a different connection."
  (interactive "P")
  (let* ((name (my/redis--saved-pick "Run saved: "))
         (e    (alist-get name my/redis-saved-commands nil nil #'equal))
         (conn (if arg
                   (my/redis--read-conn "Run on connection: ")
                 (progn (my/redis--ensure-connections)
                        (my/redis--conn-by-name (plist-get e :conn)))))
         (db   (or (plist-get e :db) (plist-get conn :db) 0)))
    (pcase (plist-get e :kind)
      ('keys (my/redis--open-keys conn db (plist-get e :pattern) (plist-get e :type)
                                  (plist-get e :limit) (plist-get e :sort-col)
                                  (plist-get e :sort-desc)))
      ('key  (my/redis--open-key conn db (plist-get e :key)))
      ('raw  (my/redis--open-replies conn db (plist-get e :lines)
                                     (format "Redis %s @ %s" name (plist-get conn :name))))
      (k (user-error "Unknown saved kind %s" k)))))

(defun my/redis-delete-saved ()
  ":: Delete a saved command (SPC d R d)."
  (interactive)
  (let ((name (my/redis--saved-pick "Delete saved: ")))
    (setf (alist-get name my/redis-saved-commands nil 'remove #'equal) nil)
    (my/redis--saved-persist)
    (message "Deleted saved %S" name)))

(provide 'my-redis-saved)
