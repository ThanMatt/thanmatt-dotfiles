;;; gitlab/mr.el --- GitLab: merge request create/edit via glab -*- lexical-binding: t; -*-

;; :: ============================================================
;; :: Merge Request Creation (via glab CLI)
;; :: ============================================================

(defvar my/gitlab-mr-template-file
  (expand-file-name "templates/merge_request_template.md" my/notes-dir)
  "Path to the merge request description template.")

(defvar-local my/gitlab-mr--title nil
  "Title captured for the MR being composed in this buffer.")
(defvar-local my/gitlab-mr--target nil
  "Target branch captured for the MR being composed in this buffer.")
(defvar-local my/gitlab-mr--source nil
  "Source branch captured for the MR being composed in this buffer.")
(defvar-local my/gitlab-mr--draft nil
  "Whether the MR being composed in this buffer is a draft.")
(defvar-local my/gitlab-mr--directory nil
  "Repository directory the MR should be created from.")
(defvar-local my/gitlab-mr--iid nil
  "IID of the existing MR being edited in this buffer.")

(defun my/gitlab-mr--git (dir &rest args)
  "Run git with ARGS in DIR and return trimmed stdout, or nil on failure."
  (let ((default-directory dir))
    (with-temp-buffer
      (when (zerop (apply #'process-file "git" nil t nil args))
        (string-trim (buffer-string))))))

(defun my/gitlab-mr--current-branch (dir)
  "Return the current git branch in DIR."
  (my/gitlab-mr--git dir "rev-parse" "--abbrev-ref" "HEAD"))

(defun my/gitlab-mr--default-branch (dir)
  "Return the remote default branch in DIR, falling back to main/master."
  (let ((ref (my/gitlab-mr--git dir "symbolic-ref" "--short" "refs/remotes/origin/HEAD")))
    (cond
     (ref (replace-regexp-in-string "^origin/" "" ref))
     ((my/gitlab-mr--git dir "rev-parse" "--verify" "--quiet" "main") "main")
     (t "master"))))

(defun my/gitlab-mr--last-subject (dir)
  "Return the subject line of the latest commit in DIR."
  (my/gitlab-mr--git dir "log" "-1" "--pretty=%s"))

(defun my/gitlab-create-mr ()
  "Interactively create a GitLab merge request using glab and the MR template.
Prompts for title, target branch and draft status, then opens an editable
buffer pre-filled with `my/gitlab-mr-template-file'. Press \\[my/gitlab-mr-submit]
to create the MR or \\[my/gitlab-mr-cancel] to abort."
  (interactive)
  (unless (executable-find "glab")
    (error "glab CLI not found on PATH"))
  (let* ((dir (or (vc-root-dir)
                  (error "Not inside a version-controlled repository")))
         (source (or (my/gitlab-mr--current-branch dir)
                     (error "Could not determine current branch")))
         (default-branch (my/gitlab-mr--default-branch dir))
         (title (read-string "MR title: " (my/gitlab-mr--last-subject dir)))
         (target (read-string "Target branch: " default-branch))
         (draft (y-or-n-p "Mark as draft? "))
         (buf (get-buffer-create "*GitLab MR*")))
    (when (string-blank-p title)
      (error "MR title cannot be empty"))
    (with-current-buffer buf
      (erase-buffer)
      (if (file-readable-p my/gitlab-mr-template-file)
          (insert-file-contents my/gitlab-mr-template-file)
        (message "Template not found at %s; starting blank" my/gitlab-mr-template-file))
      (if (fboundp 'gfm-mode) (gfm-mode) (text-mode))
      (setq my/gitlab-mr--title title
            my/gitlab-mr--target target
            my/gitlab-mr--source source
            my/gitlab-mr--draft draft
            my/gitlab-mr--directory dir)
      (use-local-map (copy-keymap (current-local-map)))
      (local-set-key (kbd "C-c C-c") #'my/gitlab-mr-submit)
      (local-set-key (kbd "C-c C-k") #'my/gitlab-mr-cancel)
      (setq header-line-format
            (format " %s%s → %s   |   C-c C-c: create   C-c C-k: cancel"
                    (if draft "[DRAFT] " "") source target))
      (goto-char (point-min)))
    (pop-to-buffer buf)
    (message "Edit the MR description, then C-c C-c to create (C-c C-k to cancel)")))

(defun my/gitlab-copy-mr-link ()
  "Copy the MR link for the current branch to the kill-ring.
Uses glab to look up the merge request whose source branch matches
the current branch. If none is found, reports that no MR exists yet."
  (interactive)
  (unless (executable-find "glab")
    (error "glab CLI not found on PATH"))
  (let* ((dir (or (vc-root-dir)
                  (error "Not inside a version-controlled repository")))
         (branch (or (my/gitlab-mr--current-branch dir)
                     (error "Could not determine current branch")))
         (default-directory dir))
    (with-temp-buffer
      (if (zerop (process-file "glab" nil t nil
                               "mr" "list"
                               "--source-branch" branch
                               "--output" "json"))
          (let* ((json-object-type 'hash-table)
                 (json-array-type 'list)
                 (json-key-type 'string)
                 (mrs (progn (goto-char (point-min)) (json-read)))
                 (mr (car mrs)))
            (if mr
                (let ((url (gethash "web_url" mr)))
                  (kill-new url)
                  (message "MR link copied: %s" url))
              (message "No MR for this branch yet")))
        (message "No MR for this branch yet")))))

(defun my/gitlab-browse-remote ()
  "Open the current repository's GitLab project page in the browser.
Uses `glab repo view --web', which resolves the page from the repo's
origin remote -- no URL parsing needed here."
  (interactive)
  (unless (executable-find "glab")
    (error "glab CLI not found on PATH"))
  (let* ((dir (or (vc-root-dir)
                  (error "Not inside a version-controlled repository")))
         (default-directory dir))
    (with-temp-buffer
      (unless (zerop (process-file "glab" nil t nil "repo" "view" "--web"))
        (error "glab repo view --web failed: %s" (string-trim (buffer-string)))))))

(defun my/gitlab-edit-mr ()
  "Edit the description of the existing MR for the current branch.
Errors if no MR exists. Otherwise opens an editable buffer pre-filled with
the MR's current description (markdown). Press \\[my/gitlab-mr-edit-submit]
to save or \\[my/gitlab-mr-cancel] to abort."
  (interactive)
  (unless (executable-find "glab")
    (error "glab CLI not found on PATH"))
  (let* ((dir (or (vc-root-dir)
                  (error "Not inside a version-controlled repository")))
         (source (or (my/gitlab-mr--current-branch dir)
                     (error "Could not determine current branch")))
         (default-directory dir)
         (mr (with-temp-buffer
               (unless (zerop (process-file "glab" nil t nil
                                            "mr" "list"
                                            "--source-branch" source
                                            "--output" "json"))
                 (error "No MR for this branch yet"))
               (let* ((json-object-type 'hash-table)
                      (json-array-type 'list)
                      (json-key-type 'string))
                 (goto-char (point-min))
                 (car (json-read))))))
    (unless mr
      (error "No MR for this branch yet"))
    (let* ((iid (gethash "iid" mr))
           (title (gethash "title" mr))
           (description (or (gethash "description" mr) ""))
           (buf (get-buffer-create "*GitLab MR Edit*")))
      (with-current-buffer buf
        (erase-buffer)
        (insert description)
        (if (fboundp 'gfm-mode) (gfm-mode) (text-mode))
        (setq my/gitlab-mr--iid iid
              my/gitlab-mr--title title
              my/gitlab-mr--source source
              my/gitlab-mr--directory dir)
        (use-local-map (copy-keymap (current-local-map)))
        (local-set-key (kbd "C-c C-c") #'my/gitlab-mr-edit-submit)
        (local-set-key (kbd "C-c C-k") #'my/gitlab-mr-cancel)
        (setq header-line-format
              (format " Edit MR !%s: %s   |   C-c C-c: save   C-c C-k: cancel"
                      iid title))
        (goto-char (point-min)))
      (pop-to-buffer buf)
      (message "Edit the MR description, then C-c C-c to save (C-c C-k to cancel)"))))

(defun my/gitlab-mr-edit-submit ()
  "Save the edited MR description in the current buffer via glab."
  (interactive)
  (let* ((iid my/gitlab-mr--iid)
         (dir my/gitlab-mr--directory)
         (description (buffer-substring-no-properties (point-min) (point-max)))
         (default-directory dir)
         (out-buf (get-buffer-create "*glab mr update*")))
    (unless iid
      (error "No MR associated with this buffer"))
    (with-current-buffer out-buf
      (let ((inhibit-read-only t)) (erase-buffer))
      (setq default-directory dir))
    (message "Updating merge request...")
    (make-process
     :name "glab-mr-update"
     :buffer out-buf
     :command (list "glab" "mr" "update" (number-to-string iid)
                    "--description" description)
     :sentinel
     (lambda (proc _event)
       (when (memq (process-status proc) '(exit signal))
         (if (zerop (process-exit-status proc))
             (progn
               (when (buffer-live-p (get-buffer "*GitLab MR Edit*"))
                 (kill-buffer "*GitLab MR Edit*"))
               (message "MR !%s updated" iid))
           (progn
             (pop-to-buffer out-buf)
             (message "glab mr update failed (see *glab mr update*)"))))))))

(defun my/gitlab-mr-cancel ()
  "Cancel MR composition."
  (interactive)
  (when (yes-or-no-p "Discard this merge request? ")
    (kill-buffer (current-buffer))
    (message "MR creation cancelled")))

(defun my/gitlab-mr-submit ()
  "Submit the merge request composed in the current buffer via glab."
  (interactive)
  (let* ((title my/gitlab-mr--title)
         (target my/gitlab-mr--target)
         (source my/gitlab-mr--source)
         (draft my/gitlab-mr--draft)
         (dir my/gitlab-mr--directory)
         (description (buffer-substring-no-properties (point-min) (point-max)))
         (default-directory dir)
         (args (append
                (list "mr" "create"
                      "--source-branch" source
                      "--target-branch" target
                      "--title" title
                      "--description" description
                      "--no-editor"
                      "--yes")
                (when draft (list "--draft"))))
         (out-buf (get-buffer-create "*glab mr create*")))
    (with-current-buffer out-buf
      (let ((inhibit-read-only t)) (erase-buffer))
      (setq default-directory dir))
    (message "Creating merge request...")
    (make-process
     :name "glab-mr-create"
     :buffer out-buf
     :command (cons "glab" args)
     :sentinel
     (lambda (proc _event)
       (when (memq (process-status proc) '(exit signal))
         (with-current-buffer (process-buffer proc)
           (goto-char (point-max)))
         (if (zerop (process-exit-status proc))
             (let ((url (with-current-buffer out-buf
                          (when (re-search-backward "https?://[^ \n]+" nil t)
                            (match-string 0)))))
               (when (buffer-live-p (get-buffer "*GitLab MR*"))
                 (kill-buffer "*GitLab MR*"))
               (if url
                   (progn (kill-new url)
                          (message "MR created: %s (copied to kill-ring)" url))
                 (message "MR created successfully")))
           (progn
             (pop-to-buffer out-buf)
             (message "glab mr create failed (see *glab mr create*)"))))))))

;;; mr.el ends here
