;;; modules/claude.el -*- lexical-binding: t; -*-

(defvar my/claude-models
  '("sonnet" "opus" "haiku")
  ":: Model aliases for `claude --model'. The CLI resolves each alias to the
current model in that family, so this list never goes stale.")

(defvar my/claude-efforts
  '("low" "medium" "high" "xhigh" "max")
  ":: Effort levels accepted by claude --effort.")

(defun my/claude-ask-region (start end)
  ":: Open an interactive Claude session with the selected region as context.
Prompts for model, effort, and query in sequence.
Empty query defaults to 'Explain this snippet.'
Runs: claude --model <model> --effort <effort> \"$(cat tmpfile)\""
  (interactive "r")
  (let* ((code   (buffer-substring-no-properties start end))
         (file   (or (buffer-file-name) (buffer-name)))
         (line   (line-number-at-pos start))
         (model  (completing-read "Model: " my/claude-models nil t nil nil "sonnet"))
         (effort (completing-read "Effort: " my/claude-efforts nil t nil nil "medium"))
         (input  (read-string "Ask Claude (RET to explain): "))
         (query  (if (string-blank-p input) "Explain this snippet." input))
         (prompt (format "File: %s:%d\n\n```\n%s\n```\n\n%s" file line code query))
         (tmp    (make-temp-file "claude-ctx-" nil ".txt")))
    (with-temp-file tmp (insert prompt))
    (let ((existing (get-buffer "*claude-ask*")))
      (when (and existing (buffer-live-p existing))
        (kill-buffer existing)))
    (let ((buf (get-buffer-create "*claude-ask*")))
      (pop-to-buffer buf)
      (vterm-mode)
      (run-with-timer 0.3 nil
                      (lambda ()
                        (when (buffer-live-p buf)
                          (vterm-send-string
                           (format "claude --model %s --effort %s \"$(cat %s)\""
                                   (shell-quote-argument model)
                                   (shell-quote-argument effort)
                                   (shell-quote-argument tmp)))
                          (vterm-send-return)))))))
