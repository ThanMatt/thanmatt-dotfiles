;;; uuid.el --- UUID generator for Doom Emacs -*- lexical-binding: t; -*-

;; :: Seed Emacs's PRNG from real entropy once at load. Without this `random'
;; :: starts from a fixed seed each session, so the first UUIDs would repeat.
(random t)

(defun my/uuid-generate ()
  ":: Return a random RFC 4122 version-4 UUID string (8-4-4-4-12 hex).
The 13th hex digit is fixed to 4 (version) and the 17th is forced into the
8/9/a/b range (variant), per the spec; the rest is drawn from `random'."
  (let ((r (lambda () (random 65536))))
    (format "%04x%04x-%04x-4%03x-%04x-%04x%04x%04x"
            (funcall r) (funcall r)                      ; :: group 1 (8 hex)
            (funcall r)                                  ; :: group 2 (4 hex)
            (logand (funcall r) #x0fff)                  ; :: group 3: 4xxx (version)
            (logior #x8000 (logand (funcall r) #x3fff))  ; :: group 4: variant bits
            (funcall r) (funcall r) (funcall r))))       ; :: group 5 (12 hex)

(defun my/uuid-insert ()
  ":: Generate a v4 UUID, insert it at point, and copy it to the kill-ring.
In a read-only buffer it skips the insert and just copies + echoes the value.
The copy rides `kill-new', so `wl-copy' (see config.el) lands it on the
Wayland clipboard too."
  (interactive)
  (let ((uuid (my/uuid-generate)))
    (unless buffer-read-only
      (insert uuid))
    (kill-new uuid)
    (message "UUID: %s (copied)" uuid)))

;; :: Key binding: SPC i u (Doom's "insert" leader prefix)
(map! :leader
      :desc "Insert UUID"
      "i u" #'my/uuid-insert)

(provide 'uuid)
;;; uuid.el ends here
