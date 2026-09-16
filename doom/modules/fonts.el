;;; fonts.el --- Keep the frame font from shrinking on reload -*- lexical-binding: t; -*-

;; :: ============================================================
;; :: Font size repair
;; :: ============================================================
;;
;; :: Symptom: after `SPC h r r' (`doom/reload') the GUI frame's text collapses
;; :: to an unreadable size and only restarting Emacs brings it back.
;;
;; :: Cause: `doom-init-fonts-h' re-applies `doom-font' and then mirrors the
;; :: result into the `user' custom theme, building that spec from
;; :: `(face-attribute FACE ATTR)' -- with no FRAME argument, so it reads the
;; :: *selected* frame.  This session runs `emacs --daemon=notes', and a daemon's
;; :: initial frame is a terminal frame whose default `:height' is 1 (height is
;; :: meaningless on a tty).  If that frame is the selected one when the capture
;; :: happens, `:height 1' lands in the `user' theme -- which applies to *every*
;; :: frame, so the GUI frame renders at pixelsize 1.  It then survives further
;; :: reloads because each one re-captures the corrupted value.
;;
;; :: Observed on 2026-09-14: the `user' theme-face for `default' held
;; :: `:height 1' and the GUI frame's font was
;; ::   -CTDB-FiraCode Nerd Font-regular-normal-normal-*-1-*-*-*-m-0-iso10646-1
;; :: Stripping that `:height' and re-running `doom-init-fonts-h' with a graphic
;; :: frame selected restored pixelsize 12 without a restart.

(defun my/font--plist-without (plist prop)
  "Return PLIST with every PROP key (and its value) removed."
  (let (out)
    (while plist
      (unless (eq (car plist) prop)
        (setq out (plist-put out (car plist) (cadr plist))))
      (setq plist (cddr plist)))
    out))

(defun my/font--faces ()
  "Return the faces `doom-init-fonts-h' writes custom specs for."
  '(default fixed-pitch fixed-pitch-serif variable-pitch))

(defun my/font-purge-stale-height ()
  "Strip `:height' from the `user' custom spec of Doom's font faces.
Only `:height' is removed -- colours and other attributes Doom mirrored
into the `user' theme are left alone -- so the next `doom-init-fonts-h'
re-derives the height from `doom-font' instead of from a stale capture."
  (dolist (face (my/font--faces))
    (when-let* ((entry (assq 'user (get face 'theme-face))))
      (setcar (cdr entry)
              (mapcar (lambda (spec)
                        (list (car spec)
                              (my/font--plist-without (nth 1 spec) :height)))
                      (cadr entry))))
    (put face 'face-modified nil)))

(defun my/font--graphic-frame ()
  "Return a frame that can actually render fonts, or the selected one."
  (or (seq-find #'display-multi-font-p (frame-list))
      (selected-frame)))

;;;###autoload
(defun my/fix-fonts ()
  "Re-apply `doom-font', repairing a frame that has shrunk to pixelsize 1.
Use this instead of restarting Emacs when the text goes tiny.  Runs
automatically after `doom/reload'."
  (interactive)
  (my/font-purge-stale-height)
  (with-selected-frame (my/font--graphic-frame)
    (doom-init-fonts-h t))
  (when (called-interactively-p 'interactive)
    (message "Fonts re-applied (default height %s)"
             (face-attribute 'default :height (my/font--graphic-frame) t))))

;; :: Defence in depth: never let the capture read a terminal frame.  The
;; :: trigger was not reproducible on demand, so this guard is cheap insurance
;; :: rather than a proven cure -- `my/fix-fonts' is the reliable recovery.
(defun my/font--on-graphic-frame-a (fn &rest args)
  "Run FN with ARGS while a font-capable frame is selected."
  (with-selected-frame (my/font--graphic-frame)
    (apply fn args)))

(advice-add 'doom-init-fonts-h :around #'my/font--on-graphic-frame-a)

;; :: `SPC h r r' is the command that triggers this, so repair right after it
(add-hook 'doom-after-reload-hook #'my/fix-fonts)

(map! :leader
      :prefix "h"
      :desc "Fix shrunken fonts" "F" #'my/fix-fonts)

(provide 'fonts)
;;; fonts.el ends here
