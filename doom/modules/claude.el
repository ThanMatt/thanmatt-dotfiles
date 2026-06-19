;;; modules/claude.el -*- lexical-binding: t; -*-

(defun my/claude-ask-region (start end)
  ":: Open an interactive Claude session with the selected region as context.
Prompts for a query -- empty input defaults to 'Explain this snippet.'
Writes context to a temp file and runs: claude \"$(cat tmpfile)\""
  (interactive "r")
  (let* ((code   (buffer-substring-no-properties start end))
         (file   (or (buffer-file-name) (buffer-name)))
         (line   (line-number-at-pos start))
         (input  (read-string "Ask Claude (RET to explain): "))
         (query  (if (string-blank-p input) "Explain this snippet." input))
         (prompt (format "File: %s:%d\n\n```\n%s\n```\n\n%s" file line code query))
         (tmp    (make-temp-file "claude-ctx-" nil ".txt")))
    (with-temp-file tmp (insert prompt))
    (let ((existing (get-buffer "*claude*")))
      (when (and existing (buffer-live-p existing))
        (kill-buffer existing)))
    (let ((buf (get-buffer-create "*claude*")))
      (pop-to-buffer buf)
      (vterm-mode)
      (run-with-timer 0.3 nil
                      (lambda ()
                        (when (buffer-live-p buf)
                          (vterm-send-string
                           (format "claude \"$(cat %s)\"" (shell-quote-argument tmp)))
                          (vterm-send-return)))))))

(map! :localleader
      :desc "Ask Claude about selection" "c" #'my/claude-ask-region)
