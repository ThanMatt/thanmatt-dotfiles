;;; org-brain.el -*- lexical-binding: t; -*-

(defvar org-brain-notes-dir my/notes-dir
  "Root directory scanned for .org files.")

(defvar org-brain--last-query nil)

(defconst org-brain--max-corpus-chars 720000
  "~180K tokens -- leaves headroom in Haiku's 200K context window.")

(defun org-brain--collect-corpus ()
  "Build annotated corpus: each file prefixed with '--- FILE: /abs/path'.
Truncates at `org-brain--max-corpus-chars' with a warning."
  (let ((files (directory-files-recursively org-brain-notes-dir "\\.org$"))
        parts
        (total 0)
        truncated)
    (catch 'done
      (dolist (file files)
        (let ((entry (format "--- FILE: %s\n%s\n"
                             file
                             (with-temp-buffer
                               (insert-file-contents file)
                               (buffer-string)))))
          (setq total (+ total (length entry)))
          (if (> total org-brain--max-corpus-chars)
              (progn (setq truncated t) (throw 'done nil))
            (push entry parts)))))
    (when truncated
      (message "org-brain: corpus truncated to ~180K tokens to fit context window"))
    (mapconcat #'identity (nreverse parts) "\n")))

(defun org-brain--prompt (query corpus)
  (format "You are the user's second brain. Their annotated org-mode notes are below.
Each section is prefixed with '--- FILE: /absolute/path' so you know exactly which file it came from.

Rules:
- Ground every claim in a specific file and heading from the corpus
- Cite inline using this exact format: [[file:/absolute/path/to/file.org][* Heading Text]]
- For cross-note connections, cite both files
- Never fabricate headings -- only cite headings that exist in the corpus
- Fact lookup: answer directly then cite the source
- Idea connections: surface non-obvious links across notes
- Summaries: organize by theme, not by file

Question: %s

--- NOTES START ---
%s
--- NOTES END ---"
          query corpus))

(defun org-brain-rerun ()
  "Re-run the last org-brain query."
  (interactive)
  (if org-brain--last-query
      (org-brain-query org-brain--last-query)
    (message "No previous query to re-run.")))

(defun org-brain-yank-response ()
  "Yank the full *org-brain* buffer to the kill ring."
  (interactive)
  (with-current-buffer (get-buffer "*org-brain*")
    (kill-new (buffer-string))
    (message "Response yanked to clipboard.")))

(define-minor-mode org-brain-minor-mode
  "Keybindings for *org-brain* response buffers."
  :lighter " Brain"
  :keymap (make-sparse-keymap))

(after! evil
  (evil-define-key 'normal org-brain-minor-mode-map
    "q" #'quit-window
    "r" #'org-brain-rerun
    "y" #'org-brain-yank-response))

(defun org-brain-query (query)
  "Query your org-mode second brain with QUERY via Claude Haiku.
Opens *org-brain* in org-mode and streams the response asynchronously."
  (interactive "sQuery your second brain: ")
  (setq org-brain--last-query query)
  (let* ((buf (get-buffer-create "*org-brain*"))
         (corpus (org-brain--collect-corpus))
         (prompt (org-brain--prompt query corpus))
         (tmp (make-temp-file "org-brain-" nil ".txt")))
    (write-region prompt nil tmp)
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (org-mode)
        (insert (format "#+TITLE: %s\n#+DATE: %s\n\n"
                        query (format-time-string "%Y-%m-%d %H:%M")))
        (read-only-mode 1))
      (org-brain-minor-mode 1))
    (pop-to-buffer buf)
    (message "Querying your second brain...")
    (let ((process-environment (append '("TERM=dumb" "NO_COLOR=1") process-environment)))
    (make-process
     :name    "org-brain-query"
     :buffer  nil
     :command (list "bash" "-c"
                    (concat "claude --model claude-haiku-4-5 --print < "
                            (shell-quote-argument tmp)))
     :filter  (lambda (_proc output)
                (when (buffer-live-p buf)
                  (with-current-buffer buf
                    (let ((inhibit-read-only t))
                      (save-excursion
                        (goto-char (point-max))
                        (insert output))))))
     :sentinel (lambda (_proc event)
                 (when (string-prefix-p "finished" event)
                   (delete-file tmp)
                   (message "Second brain ready.")))))))
