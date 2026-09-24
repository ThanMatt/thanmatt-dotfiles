;;; gitlab/dash.el --- GitLab: shared dashboard layer (paging, cycling, header) -*- lexical-binding: t; -*-

;; :: ============================================================
;; :: Dashboards: my merge requests / my assigned issues / project pipelines
;; :: ============================================================
;;
;; :: `my/gitlab-my-merge-requests' (SPC o g p) and `my/gitlab-my-issues'
;; :: (SPC o g a) list your work one line each, newest first, so pending MRs
;; :: and tickets can be checked without going to Slack or GitLab.
;; :: `my/gitlab-pipelines' (SPC o g P) does the same for one project's CI
;; :: pipelines, and can watch one until it finishes.
;; ::
;; :: All three share `my/gitlab-dash--*': paging, state/scope/sort cycling
;; :: and refresh live in one place, and each dashboard supplies its own
;; :: renderer and its own RET action.

(defvar my/gitlab-dash-per-page 20
  "How many items each GitLab dashboard fetches per page.")

;; :: ------------------------------------------------------------
;; :: Shared dashboard layer
;; :: ------------------------------------------------------------

(defvar-local my/gitlab-dash--refetch nil
  "Function of (PAGE STATE SCOPE SORT) that redraws this dashboard.")
(defvar-local my/gitlab-dash--page 1
  "Page currently displayed.")
(defvar-local my/gitlab-dash--state "opened"
  "State filter currently displayed.")
(defvar-local my/gitlab-dash--scope "created_by_me"
  "Scope filter currently displayed.")
(defvar-local my/gitlab-dash--sort "created_at"
  "Field the current listing is ordered by.")
(defvar-local my/gitlab-dash--items nil
  "Objects currently displayed, in render order.")
(defvar-local my/gitlab-dash--states nil
  "States `my/gitlab-dash-cycle-state' rotates through in this buffer.")
(defvar-local my/gitlab-dash--scopes nil
  "Scopes `my/gitlab-dash-cycle-scope' rotates through in this buffer.")
(defvar-local my/gitlab-dash--sorts nil
  "Sort fields `my/gitlab-dash-cycle-sort' rotates through in this buffer.")

(defun my/gitlab-dash--next-in (value list)
  "Return the entry after VALUE in LIST, wrapping around."
  (or (cadr (member value list)) (car list)))

(defun my/gitlab-dash--go (&rest overrides)
  "Re-fetch this dashboard.
OVERRIDES is a plist of :page, :state, :scope and :sort; anything absent
keeps the buffer's current value."
  (unless (functionp my/gitlab-dash--refetch)
    (user-error "Not a GitLab dashboard buffer"))
  (funcall my/gitlab-dash--refetch
           (or (plist-get overrides :page) my/gitlab-dash--page)
           (or (plist-get overrides :state) my/gitlab-dash--state)
           (or (plist-get overrides :scope) my/gitlab-dash--scope)
           (or (plist-get overrides :sort) my/gitlab-dash--sort)))

(defun my/gitlab-dash-refresh ()
  "Re-fetch the current page."
  (interactive)
  (my/gitlab-dash--go))

(defun my/gitlab-dash-next-page ()
  "Show the next page."
  (interactive)
  (if (< (length my/gitlab-dash--items) my/gitlab-dash-per-page)
      (message "Already on the last page")
    (my/gitlab-dash--go :page (1+ my/gitlab-dash--page))))

(defun my/gitlab-dash-prev-page ()
  "Show the previous page."
  (interactive)
  (if (<= my/gitlab-dash--page 1)
      (message "Already on the first page")
    (my/gitlab-dash--go :page (1- my/gitlab-dash--page))))

(defun my/gitlab-dash-cycle-state ()
  "Cycle the state filter, returning to page 1."
  (interactive)
  (my/gitlab-dash--go
   :page 1 :state (my/gitlab-dash--next-in my/gitlab-dash--state my/gitlab-dash--states)))

(defun my/gitlab-dash-cycle-scope ()
  "Cycle the scope filter, returning to page 1."
  (interactive)
  (if (< (length my/gitlab-dash--scopes) 2)
      (message "Only one scope for this view")
    (my/gitlab-dash--go
     :page 1 :scope (my/gitlab-dash--next-in my/gitlab-dash--scope my/gitlab-dash--scopes))))

(defun my/gitlab-dash-cycle-sort ()
  "Cycle the sort field, returning to page 1."
  (interactive)
  (my/gitlab-dash--go
   :page 1 :sort (my/gitlab-dash--next-in my/gitlab-dash--sort my/gitlab-dash--sorts)))

(defun my/gitlab-dash--at-point ()
  "Return the object on the current line, or signal an error."
  (or (get-text-property (point) 'gitlab-item)
      (save-excursion
        (beginning-of-line)
        (get-text-property (point) 'gitlab-item))
      (user-error "Nothing on this line")))

(defun my/gitlab-dash-browse-at-point ()
  "Open the item on the current line in the browser."
  (interactive)
  (browse-url (gethash "web_url" (my/gitlab-dash--at-point))))

(defun my/gitlab-dash-copy-url-at-point ()
  "Copy the URL of the item on the current line."
  (interactive)
  (let ((url (gethash "web_url" (my/gitlab-dash--at-point))))
    (kill-new url)
    (message "Copied: %s" url)))

(defun my/gitlab-dash--sort-label (sort)
  "Return a short human label for the SORT field."
  (if (equal sort "updated_at") "recently updated" "newest"))

(defun my/gitlab-dash--insert-header (title scope-label state sort page count columns help)
  "Insert the common dashboard header into the current buffer."
  (insert (propertize (format "%s — %s · %s · %s · page %d\n"
                              title scope-label state
                              (my/gitlab-dash--sort-label sort) page)
                      'face 'bold))
  (insert (propertize (format "%d shown%s\n" count
                              (if (< count my/gitlab-dash-per-page) " (last page)" ""))
                      'face 'font-lock-comment-face))
  (insert (propertize (concat help "\n\n") 'face 'font-lock-comment-face))
  (insert (propertize columns 'face 'font-lock-keyword-face)))

(defun my/gitlab-dash--finish (page state scope sort items states scopes sorts)
  "Record the dashboard's filter state as buffer-local variables."
  (setq my/gitlab-dash--page page
        my/gitlab-dash--state state
        my/gitlab-dash--scope scope
        my/gitlab-dash--sort sort
        my/gitlab-dash--items items
        my/gitlab-dash--states states
        my/gitlab-dash--scopes scopes
        my/gitlab-dash--sorts sorts))

(defun my/gitlab-dash--bind (map open-fn)
  "Populate MAP with the shared dashboard keys, using OPEN-FN for RET/o."
  (define-key map (kbd "RET") open-fn)
  (define-key map (kbd "o") open-fn)
  (define-key map (kbd "b") 'my/gitlab-dash-browse-at-point)
  (define-key map (kbd "y") 'my/gitlab-dash-copy-url-at-point)
  (define-key map (kbd "n") 'my/gitlab-dash-next-page)
  (define-key map (kbd "p") 'my/gitlab-dash-prev-page)
  (define-key map (kbd "s") 'my/gitlab-dash-cycle-state)
  (define-key map (kbd "t") 'my/gitlab-dash-cycle-scope)
  (define-key map (kbd "S") 'my/gitlab-dash-cycle-sort)
  (define-key map (kbd "r") 'my/gitlab-dash-refresh)
  (define-key map (kbd "q") 'quit-window)
  map)

(defun my/gitlab-dash--evil-bind (mode-map open-fn)
  "Mirror the shared dashboard keys into evil normal state for MODE-MAP.
Uses `evil-define-key*', the function form.  `evil-define-key' is a macro:
given the symbol of a lexical variable it defers the bindings to a global
keymap variable of that name, which never exists here -- so nothing binds
and evil's own RET/b/y/n/p keep winning."
  (evil-define-key* 'normal mode-map
    (kbd "RET") open-fn
    (kbd "o") open-fn
    (kbd "b") 'my/gitlab-dash-browse-at-point
    (kbd "y") 'my/gitlab-dash-copy-url-at-point
    (kbd "n") 'my/gitlab-dash-next-page
    (kbd "p") 'my/gitlab-dash-prev-page
    (kbd "s") 'my/gitlab-dash-cycle-state
    (kbd "t") 'my/gitlab-dash-cycle-scope
    (kbd "S") 'my/gitlab-dash-cycle-sort
    (kbd "r") 'my/gitlab-dash-refresh
    (kbd "gr") 'my/gitlab-dash-refresh
    (kbd "q") 'quit-window))

(defconst my/gitlab-dash-help
  "RET/o: open  b: browser  y: copy URL  n/p: page  s: state  t: scope  S: sort  r: refresh  q: quit"
  "Help line shown at the top of every GitLab dashboard.")

;;; dash.el ends here
