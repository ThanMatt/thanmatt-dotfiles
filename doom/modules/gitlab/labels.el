;;; gitlab/labels.el --- GitLab: toggle issue labels from its org file -*- lexical-binding: t; -*-

;; :: ------------------------------------------------------------
;; :: Editing an issue's labels from its org file
;; :: ------------------------------------------------------------
;;
;; :: `my/gitlab-issue-toggle-label' (SPC o g L) works inside any issue file in
;; :: `my/gitlab-issues-dir'.  It offers every label the project can use --
;; :: project *and* inherited group labels, rendered in their own colours --
;; :: with the ones already on the issue marked and listed first.  Picking one
;; :: toggles it: applied labels come off, unapplied ones go on.
;; ::
;; :: Scoped labels (`stage::refine') need no special handling -- GitLab drops
;; :: the previous label in a scope when a new one is added, so picking
;; :: `stage::dev_review' replaces `stage::refine' server-side.

(defvar my/gitlab-labels-max-pages 10
  "Safety cap on how many pages of labels `my/gitlab--fetch-all-labels' walks.")

(defun my/gitlab-issue--current-id ()
  "Return the issue IID for the current buffer's file.
Signals an error unless the buffer visits a `PROJECT#<ID> - ....org' file
inside `my/gitlab-issues-dir', the same guard the other issue-file
commands use."
  (let* ((file (buffer-file-name))
         (issues-dir (my/gitlab-issues-dir))
         (filename (and file (file-name-nondirectory file))))
    (unless (and file (string-prefix-p issues-dir (expand-file-name file)))
      (user-error "This command only works on files in %s" issues-dir))
    (unless (string-match (format "^%s#\\([0-9]+\\)" (regexp-quote my/gitlab-project-name))
                          filename)
      (user-error "Filename must start with %s#<ID>" my/gitlab-project-name))
    (match-string 1 filename)))

(defun my/gitlab--label-face (label)
  "Return a face plist painting LABEL in its own GitLab colours.
Falls back to no styling when the API gives no usable hex colour."
  (let ((bg (gethash "color" label))
        (fg (gethash "text_color" label)))
    (if (and (stringp bg) (string-match-p "\\`#[0-9a-fA-F]\\{6\\}\\'" bg))
        (list :background bg
              :foreground (if (and (stringp fg)
                                   (string-match-p "\\`#[0-9a-fA-F]\\{6\\}\\'" fg))
                              fg
                            "#ffffff"))
      'default)))

(defun my/gitlab--fetch-all-labels (callback &optional page acc)
  "Collect every label available to the project, then call CALLBACK with them.
Walks pagination -- the project inherits group labels, so one page is not
enough -- stopping at `my/gitlab-labels-max-pages'."
  (let ((page (or page 1)))
    (my/gitlab--api-get-async
     (format "projects/%s/labels" (url-hexify-string my/gitlab-project-id))
     (format "per_page=100&page=%d&with_counts=false" page)
     (lambda (labels)
       (if (not (and labels (listp labels)))
           (funcall callback acc)
         (let ((all (append acc labels)))
           (if (and (= (length labels) 100) (< page my/gitlab-labels-max-pages))
               (my/gitlab--fetch-all-labels callback (1+ page) all)
             (funcall callback all))))))))

(defun my/gitlab--label-candidates (labels current)
  "Return an alist of (DISPLAY . NAME) for LABELS, CURRENT ones marked and first.
DISPLAY carries the label's colours as text properties, so the completion
UI shows the same chips GitLab does."
  (let (on off)
    (dolist (label labels)
      (unless (my/gitlab--truthy (gethash "archived" label))
        (let* ((name (gethash "name" label))
               (applied (member name current))
               (display (concat (if applied "✓ " "  ")
                                (propertize (format " %s " name)
                                            'face (my/gitlab--label-face label)))))
          (if applied (push (cons display name) on) (push (cons display name) off)))))
    (append (nreverse on) (nreverse off))))

(defun my/gitlab-issue--update-labels-line (labels)
  "Rewrite the `- *Labels:*' line of the current buffer to LABELS.
Removes the line when LABELS is empty; inserts one after Author (or URL)
when the issue had no labels at the time the file was written."
  (save-excursion
    (let ((text (and labels
                     (format "- *Labels:* %s\n" (mapconcat #'identity labels ", ")))))
      (goto-char (point-min))
      (cond
       ((re-search-forward "^- \\*Labels:\\* .*\n" nil t)
        ;; :: LITERAL, so `\\' and `&' inside a label name stay literal
        (replace-match (or text "") t t))
       ((null text) nil)
       (t (goto-char (point-min))
          (when (or (re-search-forward "^- \\*Author:\\* .*\n" nil t)
                    (progn (goto-char (point-min))
                           (re-search-forward "^- \\*URL:\\* .*\n" nil t)))
            (insert text)))))))

(defun my/gitlab-issue--apply-label (issue-id name addp buffer)
  "Add (ADDP non-nil) or remove label NAME on ISSUE-ID, then refresh BUFFER."
  (my/gitlab--api-request-async
   "PUT"
   (format "projects/%s/issues/%s"
           (url-hexify-string my/gitlab-project-id) issue-id)
   (format "%s=%s" (if addp "add_labels" "remove_labels") (url-hexify-string name))
   (lambda (issue)
     (cond
      ((or (null issue) (null (gethash "iid" issue)))
       (message "Could not %s label %s%s"
                (if addp "add" "remove") name
                (if (and issue (gethash "message" issue))
                    (format ": %s" (gethash "message" issue)) "")))
      ((not (buffer-live-p buffer))
       (message "Label %s %s, but the buffer is gone" name (if addp "added" "removed")))
      (t
       (let ((labels (gethash "labels" issue)))
         (with-current-buffer buffer
           (my/gitlab-issue--update-labels-line labels)
           (when (buffer-file-name) (save-buffer)))
         (message "%s %s — now: %s"
                  (if addp "Added" "Removed") name
                  (if labels (mapconcat #'identity labels ", ") "(none)"))))))))

;;;###autoload
(defun my/gitlab-issue-toggle-label ()
  "Toggle a GitLab label on the issue this buffer is visiting.

Offers every label the project can use -- its own and the ones inherited
from the group -- each rendered in its GitLab colour.  Labels already on
the issue are marked with a check and sorted to the top, so the same
command adds and removes.  The `- *Labels:*' line is rewritten from the
API's response and the file saved, so what you see matches the server.

Scoped labels need no care: picking `stage::dev_review' makes GitLab drop
`stage::refine' on its own."
  (interactive)
  (my/gitlab-check-config)
  (let ((issue-id (my/gitlab-issue--current-id))
        (buffer (current-buffer)))
    (message "Fetching labels...")
    (my/gitlab--fetch-all-labels
     (lambda (labels)
       (if (null labels)
           (message "No labels found for this project")
         (my/gitlab--api-get-async
          (format "projects/%s/issues/%s"
                  (url-hexify-string my/gitlab-project-id) issue-id)
          ""
          (lambda (issue)
            (if (or (null issue) (null (gethash "iid" issue)))
                (message "Could not read issue #%s" issue-id)
              (let* ((current (gethash "labels" issue))
                     (candidates (my/gitlab--label-candidates labels current))
                     (choice (completing-read
                              (format "Label for #%s (%d on, %d available): "
                                      issue-id (length current) (length candidates))
                              (my/gitlab--completion-table candidates) nil t))
                     (name (cdr (assoc choice candidates))))
                (if (null name)
                    (message "No label selected")
                  (my/gitlab-issue--apply-label
                   issue-id name (not (member name current)) buffer))))))))) ))

;;; labels.el ends here
