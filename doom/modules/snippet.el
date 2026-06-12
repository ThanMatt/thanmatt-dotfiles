(defun my/capture-to-snippet-file (start end)
  "Append selected region to a file in the notes snippets/ dir with a source link and title.
Ensures the file ends with a .org extension."
  (interactive "r")
  (let* ((snippet-dir (expand-file-name "snippets/" my/notes-dir))
         ;; 1. Ensure the directory exists
         (_ (unless (file-exists-p snippet-dir)
              (make-directory snippet-dir t)))
         ;; 2. Get list of files
         (files (directory-files snippet-dir nil "^[^.]"))
         (selected-file (completing-read "Append to file: " files))
         ;; 3. Ensure the filename ends in .org
         (final-filename (if (string-match-p "\\.org$" selected-file)
                             selected-file
                           (concat selected-file ".org")))
         (target-path (expand-file-name final-filename snippet-dir))
         ;; 4. Ask for a brief description/title
         (snippet-title (read-string "Brief description of this finding: "))
         ;; 5. Prepare Metadata
         (source-path (or (buffer-file-name) "No file"))
         (source-name (if (buffer-file-name) 
                          (file-name-nondirectory (buffer-file-name)) 
                        (buffer-name)))
         (snippet-text (buffer-substring-no-properties start end))
         (timestamp (format-time-string "[%Y-%m-%d %H:%M]"))
         ;; 6. Construct the entry
         (entry (format "* %s | [[file:%s][%s]] -- %s\n===============\n%s\n===============\n\n\n"
                        (if (string-empty-p snippet-title) "Untitled Snippet" snippet-title)
                        source-path
                        source-name
                        timestamp
                        snippet-text)))
    
    ;; 7. Append and clean up
    (append-to-file entry nil target-path)
    (message "Finding saved to %s" final-filename)
    (deactivate-mark)))

;; --- Doom Emacs Keybinding ---
(map! :leader
      (:prefix-map ("n" . "notes")
       :desc "Save snippet/finding" "s" #'my/capture-to-snippet-file))
