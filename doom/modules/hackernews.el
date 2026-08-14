;;; modules/hackernews.el -*- lexical-binding: t; -*-

;; :: A tiny Hacker News reader that lives in one reusable buffer.
;; ::
;; ::   SPC o h          open the front page
;; ::   RET / mouse-1    activate the title/comments link (or a link inside a comment)
;; ::   <tab>/<backtab>  jump between links
;; ::   C-o              go back to the previous page (jumplist-style)
;; ::   ] / [            next / previous page of the current feed
;; ::   gf               cycle feed (front → new → ask → show)
;; ::   r / gr           reload the current page (busts its cache)
;; ::   gx               open the article in the external browser
;; ::   q                bury the buffer
;; ::
;; :: Localleader (`,'):
;; ::   , o   open the article URL in the web browser
;; ::   , c   open the HN discussion page in the web browser
;; ::   , h   jump back to the front page
;; ::   , f   cycle feed   , F   select feed by name
;; ::   , n   next page   , p   previous page
;; ::   , r   reload   , b   back
;; ::
;; :: Pages are cached in `my/hn--cache' for the session, so revisiting an
;; :: already-loaded story or the front page is instant. Reload to refetch.

(require 'url)
(require 'shr)

;; :: Algolia's HN API hands back a story *with its whole comment tree* in a
;; :: single request -- far nicer than the Firebase API's one-call-per-item.
;; ::
;; :: Listing feeds are (id label . plist), where the plist holds:
;; ::   :url    endpoint path, taking a 0-indexed page number
;; ::   :deep   path used for page > 0 instead of :url, when the feed's own
;; ::           pool doesn't paginate. Because it is a *different* ranking
;; ::           than :url, the two sources overlap, so deep pages are deduped
;; ::           against page 0 (see `my/hn--baseline-page')
;; ::   :days   recency window; results older than this are filtered out
;; ::
;; :: `:days' is load-bearing, not a nicety. The `/search' endpoint with an
;; :: empty query ranks by points over *all of HN history*, so an unfiltered
;; :: `tags=story' page 1 returns the highest-scoring posts ever written --
;; :: years old. The same trap applies to `ask_hn'/`show_hn' on page 0. Pinning
;; :: a window turns "top of all time" into "top of the last N days", which is
;; :: what a front page tail should be.
;; ::
;; :: `front' still uses HN's own front-page ranking for page 0, but that tag is
;; :: a small pool that is mostly stale: ~180 items of which ~125 are months-old
;; :: job posts and ~20 are stragglers that kept the tag. The window prunes both,
;; :: leaving roughly one real page -- hence `:deep' for anything past it.
;; :: `new' is newest-first (already time-ordered), so it needs no window.
(defconst my/hn--page-size 30
  ":: Stories requested (and numbered) per listing page.")

(defconst my/hn--api-base "https://hn.algolia.com/api/v1/"
  ":: Root of the Algolia HN API.")

(defconst my/hn--feeds
  '((front "Front Page"
     :url  "search?tags=front_page&page=%d"
     :deep "search?tags=story&page=%d"
     :days 3)
    (new   "Newest"  :url "search_by_date?tags=story&page=%d")
    (ask   "Ask HN"  :url "search?tags=ask_hn&page=%d"  :days 7)
    (show  "Show HN" :url "search?tags=show_hn&page=%d" :days 7))
  ":: Listing feeds the front buffer can switch between.")

(defconst my/hn--item-url-fmt
  "https://hn.algolia.com/api/v1/items/%s"
  ":: Item (story + nested comments) endpoint, takes an id.")

(defvar my/hn--cache (make-hash-table :test 'equal)
  ":: Session cache: page-key string -> parsed JSON data.")

;; :: Per-buffer navigation + context. Declared up front so byte-compile and
;; :: `setq-local' are happy.
(defvar-local my/hn--current nil ":: Plist of the page currently shown.")
(defvar-local my/hn--history nil ":: Stack of (page . point) for `C-o' back.")
(defvar-local my/hn--page-url nil ":: External article URL for the current page.")
(defvar-local my/hn--page-hn-url nil ":: HN discussion URL for the current page.")

;;; :: Faces -----------------------------------------------------------------

(defface my/hn-title  '((t :inherit link :weight bold :underline nil))
  ":: Story title link.")
(defface my/hn-domain '((t :inherit shr-link :slant italic))
  ":: (example.com) domain hint.")
(defface my/hn-meta   '((t :inherit shadow))
  ":: Points / author / time metadata.")
(defface my/hn-meta-link '((t :inherit link :underline nil))
  ":: The clickable \"N comments\" affordance.")
(defface my/hn-author '((t :inherit font-lock-keyword-face))
  ":: Comment author.")
(defface my/hn-rule   '((t :inherit shadow))
  ":: Separator rules.")

;;; :: Small helpers ---------------------------------------------------------

(defun my/hn--get (key alist)
  ":: alist-get with a symbol KEY, tolerating string-or-symbol confusion."
  (alist-get key alist))

(defun my/hn--job-p (hit)
  ":: Non-nil if HIT is a job posting (Algolia tags these `job', and returns
them with no points or comment count)."
  (member "job" (my/hn--get '_tags hit)))

(defun my/hn--domain (url)
  ":: Bare host of URL, www. stripped, or nil."
  (when (and url (string-match "\\`https?://\\(?:www\\.\\)?\\([^/]+\\)" url))
    (match-string 1 url)))

(defun my/hn--relative-time (epoch)
  ":: \"3h ago\"-style string from an EPOCH second count."
  (if (not (numberp epoch)) ""
    (let ((d (- (float-time) epoch)))
      (cond ((< d 3600)  (format "%dm ago" (max 1 (floor d 60))))
            ((< d 86400) (format "%dh ago" (floor d 3600)))
            (t           (format "%dd ago" (floor d 86400)))))))

(defun my/hn--strip-html (html)
  ":: Crude HTML -> text fallback when libxml is unavailable."
  (if (not (stringp html)) ""
    (let ((s html))
      (setq s (replace-regexp-in-string "<p>" "\n\n" s))
      (setq s (replace-regexp-in-string "<[^>]+>" "" s))
      (dolist (p '(("&gt;" . ">") ("&lt;" . "<") ("&quot;" . "\"")
                   ("&#x27;" . "'") ("&#x2F;" . "/") ("&amp;" . "&")))
        (setq s (replace-regexp-in-string (regexp-quote (car p)) (cdr p) s)))
      (string-trim s))))

(defun my/hn--html-to-string (html indent-cols)
  ":: Render comment HTML to formatted text, wrapped to fit INDENT-COLS.
Uses `shr' (keeps links clickable) and falls back to a tag strip."
  (cond
   ((not (stringp html)) "")
   ((fboundp 'libxml-parse-html-region)
    (with-temp-buffer
      (insert html)
      (let* ((dom (libxml-parse-html-region (point-min) (point-max)))
             (shr-width (max 40 (- 92 indent-cols)))
             (shr-use-fonts nil)
             (shr-inhibit-images t)
             (shr-bullet "• "))
        (erase-buffer)
        (shr-insert-document dom)
        (string-trim (buffer-string)))))
   (t (my/hn--strip-html html))))

(defun my/hn--indent (s cols)
  ":: Prefix every line of S with COLS spaces."
  (if (<= cols 0) s
    (let ((pad (make-string cols ?\s)))
      (mapconcat (lambda (l) (concat pad l)) (split-string s "\n") "\n"))))

;;; :: Networking ------------------------------------------------------------

(defun my/hn--fetch (url callback)
  ":: GET URL asynchronously, parse JSON, and call CALLBACK with the data."
  (url-retrieve
   url
   (lambda (status)
     (let ((err (plist-get status :error))
           (buf (current-buffer)))
       (unwind-protect
           (if err
               (message "HN: fetch failed: %S" err)
             (goto-char (point-min))
             (when (re-search-forward "\n\n" nil t)
               (condition-case e
                   (let ((data (json-parse-buffer
                                :object-type 'alist
                                :array-type 'list
                                :null-object nil
                                :false-object nil)))
                     (funcall callback data))
                 (error (message "HN: parse error: %S" e)))))
         (when (buffer-live-p buf) (kill-buffer buf)))))
   nil t t))

;;; :: Page keys / dispatch --------------------------------------------------

(defun my/hn--page-num (page)
  ":: 0-indexed front-page number for PAGE, defaulting to 0."
  (or (plist-get page :page) 0))

(defun my/hn--feed-id (page)
  ":: Feed id for PAGE, defaulting to `front'."
  (or (plist-get page :feed) 'front))

(defun my/hn--feed-entry (page)
  ":: (id label . plist) entry for PAGE's feed."
  (assq (my/hn--feed-id page) my/hn--feeds))

(defun my/hn--feed-prop (page prop)
  ":: Value of PROP in PAGE's feed entry, or nil."
  (plist-get (cddr (my/hn--feed-entry page)) prop))

(defun my/hn--recent-cutoff (days)
  ":: Epoch second DAYS ago, floored to the hour.
Rounding keeps the cutoff identical for every page fetched in the same hour,
so consecutive pages index into one stable result set instead of sliding out
from under each other between requests."
  (- (* 3600 (floor (float-time) 3600)) (* days 86400)))

(defun my/hn--page-key (page)
  ":: Stable cache key for PAGE."
  (pcase (plist-get page :type)
    ('front (format "front:%s:%d" (my/hn--feed-id page) (my/hn--page-num page)))
    ('item  (format "item:%s" (plist-get page :id)))))

(defun my/hn--baseline-page (page)
  ":: Page whose stories PAGE must not repeat, or nil if it can't repeat any.
Only a `:deep' page needs this: it is drawn from a points-ranked search while
page 0 comes from HN's own front-page ranking, and the same story can sit in
both. Deep pages are disjoint slices of one ordering, so they never collide
with each other -- and a feed without `:deep' paginates a single ordering the
whole way down, so it needs no filtering at all."
  (when (and (eq (plist-get page :type) 'front)
             (> (my/hn--page-num page) 0)
             (my/hn--feed-prop page :deep))
    (list :type 'front :feed (my/hn--feed-id page) :page 0)))

(defun my/hn--page-ids (page)
  ":: objectIDs of PAGE's cached hits; nil for a nil or uncached PAGE."
  (when page
    (mapcar (lambda (hit) (my/hn--get 'objectID hit))
            (my/hn--get 'hits (gethash (my/hn--page-key page) my/hn--cache)))))

(defun my/hn--page-api-url (page)
  ":: API endpoint for PAGE.
Deeper pages swap in the feed's `:deep' path when it has one, and every feed
with a `:days' window gets a `created_at_i' floor so an empty-query search
ranks by points *within that window* rather than across all of HN history."
  (pcase (plist-get page :type)
    ('front
     (let* ((pg   (my/hn--page-num page))
            (path (or (and (> pg 0) (my/hn--feed-prop page :deep))
                      (my/hn--feed-prop page :url)))
            (days (my/hn--feed-prop page :days)))
       (concat my/hn--api-base
               (format path pg)
               (format "&hitsPerPage=%d" my/hn--page-size)
               ;; :: %%3E escapes to "%3E", the URL encoding of ">" -- Algolia
               ;; :: 400s on a raw one.
               (when days
                 (format "&numericFilters=created_at_i%%3E%d"
                         (my/hn--recent-cutoff days))))))
    ('item (format my/hn--item-url-fmt (plist-get page :id)))))

;;; :: Rendering -------------------------------------------------------------

(defun my/hn--render-front (data)
  ":: Draw the front-page story list from DATA."
  (let ((pg    (my/hn--page-num my/hn--current))
        (label (nth 1 (my/hn--feed-entry my/hn--current))))
    (setq my/hn--page-url    "https://news.ycombinator.com/news"
          my/hn--page-hn-url  "https://news.ycombinator.com/news")
    (insert (propertize (format "  Hacker News — %s%s\n" label
                                (if (> pg 0) (format " · p%d" (1+ pg)) ""))
                        'face 'my/hn-title))
    (insert (propertize (concat "  " (make-string 38 ?─) "\n\n") 'face 'my/hn-rule)))
  (let* ((i    (* my/hn--page-size (my/hn--page-num my/hn--current)))
         ;; :: Stories already shown on the baseline page, so a deep page
         ;; :: doesn't repeat what page 0 just listed.
         (seen (my/hn--page-ids (my/hn--baseline-page my/hn--current)))
         ;; :: Also drop YC "Is Hiring" job posts: Algolia returns them with no
         ;; :: points/comments, so they'd render as misleading "0 points" noise.
         (hits (seq-remove (lambda (hit)
                             (or (my/hn--job-p hit)
                                 (member (my/hn--get 'objectID hit) seen)))
                           (my/hn--get 'hits data))))
    (unless hits
      (insert (propertize "  No more stories — press [ to go back.\n" 'face 'my/hn-meta)))
    (dolist (hit hits)
      (let* ((title (or (my/hn--get 'title hit) "(untitled)"))
             (url   (my/hn--get 'url hit))
             (id    (my/hn--get 'objectID hit))
             (pts   (or (my/hn--get 'points hit) 0))
             (auth  (or (my/hn--get 'author hit) "?"))
             (ncomm (or (my/hn--get 'num_comments hit) 0))
             (when* (my/hn--get 'created_at_i hit)))
        (cl-incf i)
        (insert (propertize (format "%2d. " i) 'face 'my/hn-meta))
        (insert-text-button title
                            'face 'my/hn-title 'follow-link t
                            'hn-url url 'hn-id id 'action #'my/hn--btn-title
                            'help-echo (or url "Open comments"))
        (insert "\n      ")
        (when-let ((dom (my/hn--domain url)))
          (insert (propertize (format "(%s) " dom) 'face 'my/hn-domain)))
        (insert (propertize (format "%d points · %s · " pts auth) 'face 'my/hn-meta))
        (insert-text-button (format "%d comments" ncomm)
                            'face 'my/hn-meta-link 'follow-link t
                            'hn-id id 'action #'my/hn--btn-comments
                            'help-echo "Read discussion")
        (insert (propertize (format " · %s" (my/hn--relative-time when*))
                            'face 'my/hn-meta))
        (insert "\n\n")))))

(defun my/hn--render-comment (node depth)
  ":: Recursively insert a comment NODE at reply DEPTH."
  (let* ((indent (* depth 2))
         (auth   (my/hn--get 'author node))
         (text   (my/hn--get 'text node))
         (when*  (my/hn--get 'created_at_i node))
         (kids   (my/hn--get 'children node)))
    ;; :: Skip fully-dead nodes; show a stub when only the body is gone.
    (when (or auth text)
      (insert (my/hn--indent
               (concat (propertize (or auth "[deleted]") 'face 'my/hn-author)
                       (propertize (format "  %s" (my/hn--relative-time when*))
                                   'face 'my/hn-meta))
               indent))
      (insert "\n")
      (insert (my/hn--indent (if text (my/hn--html-to-string text indent)
                               (propertize "[deleted]" 'face 'my/hn-meta))
                             indent))
      (insert "\n\n"))
    (dolist (kid kids)
      (my/hn--render-comment kid (1+ depth)))))

(defun my/hn--render-item (data)
  ":: Draw a single story page (header + nested comments) from DATA."
  (let* ((title (or (my/hn--get 'title data) "(untitled)"))
         (url   (my/hn--get 'url data))
         (id    (my/hn--get 'id data))
         (auth  (or (my/hn--get 'author data) "?"))
         (pts   (or (my/hn--get 'points data) 0))
         (text  (my/hn--get 'text data))
         (when* (my/hn--get 'created_at_i data))
         (kids  (my/hn--get 'children data)))
    (setq my/hn--page-url   url
          my/hn--page-hn-url (format "https://news.ycombinator.com/item?id=%s" id))
    (insert "  ")
    (insert-text-button title
                        'face 'my/hn-title 'follow-link t
                        'hn-url url 'hn-id id 'action #'my/hn--btn-title
                        'help-echo (or url "No external link"))
    (insert "\n  ")
    (when-let ((dom (my/hn--domain url)))
      (insert (propertize (format "(%s) " dom) 'face 'my/hn-domain)))
    (insert (propertize (format "%d points · %s · %s\n"
                                pts auth (my/hn--relative-time when*))
                        'face 'my/hn-meta))
    ;; :: Self/Ask-HN body, if any.
    (when text
      (insert "\n" (my/hn--indent (my/hn--html-to-string text 2) 2) "\n"))
    (insert (propertize (concat "\n  " (make-string 70 ?─) "\n\n") 'face 'my/hn-rule))
    (if kids
        (dolist (kid kids) (my/hn--render-comment kid 0))
      (insert (propertize "  No comments yet.\n" 'face 'my/hn-meta)))))

(defun my/hn--render (page data restore-point)
  ":: Replace the buffer with PAGE rendered from DATA, then place point."
  (with-current-buffer (my/hn--get-buffer)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (pcase (plist-get page :type)
        ('front (my/hn--render-front data))
        ('item  (my/hn--render-item data))))
    (goto-char (if restore-point (min restore-point (point-max)) (point-min)))
    (set-buffer-modified-p nil)))

(defun my/hn--show-loading (_page)
  ":: Transient placeholder while a page is in flight."
  (with-current-buffer (my/hn--get-buffer)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert (propertize "\n  Loading Hacker News…\n" 'face 'my/hn-meta)))
    (set-buffer-modified-p nil)))

;;; :: Navigation ------------------------------------------------------------

(defun my/hn--ensure (page callback)
  ":: Call CALLBACK with PAGE's data, fetching and caching it first if needed.
Runs synchronously on a cache hit. A nil PAGE calls CALLBACK with nil, so
callers can chain an optional prerequisite without branching."
  (let* ((key    (and page (my/hn--page-key page)))
         (cached (and key (gethash key my/hn--cache))))
    (cond
     ((null page) (funcall callback nil))
     (cached      (funcall callback cached))
     (t (my/hn--fetch
         (my/hn--page-api-url page)
         (lambda (data)
           (puthash key data my/hn--cache)
           (funcall callback data)))))))

(defun my/hn--load (page restore-point)
  ":: Show PAGE, fetching it -- and the baseline page it dedupes against --
if either isn't cached yet."
  (let ((key (my/hn--page-key page)))
    (unless (gethash key my/hn--cache)
      (my/hn--show-loading page))
    ;; :: The baseline has to land first: `my/hn--render-front' reads its ids
    ;; :: out of the cache to filter this page, so rendering ahead of it would
    ;; :: silently skip the dedupe.
    (my/hn--ensure
     (my/hn--baseline-page page)
     (lambda (_baseline)
       (my/hn--ensure
        page
        (lambda (data)
          ;; :: Only paint if the user hasn't navigated away meanwhile.
          (with-current-buffer (my/hn--get-buffer)
            (when (equal (my/hn--page-key my/hn--current) key)
              (my/hn--render page data restore-point)))))))))

(defun my/hn--goto (page &optional no-push)
  ":: Navigate to PAGE, pushing the current one onto the back-stack."
  (with-current-buffer (my/hn--get-buffer)
    (when (and (not no-push) my/hn--current)
      (push (cons my/hn--current (point)) my/hn--history))
    (setq my/hn--current page)
    (my/hn--load page nil)))

(defun my/hn-back ()
  ":: Return to the previous page, restoring point (jumplist-style)."
  (interactive)
  (if (null my/hn--history)
      (message "HN: no previous page")
    (let ((entry (pop my/hn--history)))
      (setq my/hn--current (car entry))
      (my/hn--load (car entry) (cdr entry)))))

(defun my/hn-reload ()
  ":: Refetch the current page, bypassing the cache."
  (interactive)
  (when my/hn--current
    (remhash (my/hn--page-key my/hn--current) my/hn--cache)
    (my/hn--load my/hn--current (point))))

(defun my/hn-home ()
  ":: Jump to the front page."
  (interactive)
  (my/hn--goto '(:type front :page 0)))

(defun my/hn-next-page ()
  ":: Go to the next page of the current listing feed."
  (interactive)
  (if (eq (plist-get my/hn--current :type) 'front)
      (my/hn--goto (list :type 'front
                         :feed (my/hn--feed-id my/hn--current)
                         :page (1+ (my/hn--page-num my/hn--current))))
    (message "HN: paging only works on a listing page")))

(defun my/hn-prev-page ()
  ":: Go to the previous page of the current listing feed."
  (interactive)
  (cond
   ((not (eq (plist-get my/hn--current :type) 'front))
    (message "HN: paging only works on a listing page"))
   ((<= (my/hn--page-num my/hn--current) 0)
    (message "HN: already on the first page"))
   (t (my/hn--goto (list :type 'front
                         :feed (my/hn--feed-id my/hn--current)
                         :page (1- (my/hn--page-num my/hn--current)))))))

(defun my/hn-cycle-feed ()
  ":: Switch to the next listing feed (front → new → ask → show → …)."
  (interactive)
  (let* ((ids  (mapcar #'car my/hn--feeds))
         (next (or (cadr (memq (my/hn--feed-id my/hn--current) ids))
                   (car ids))))
    (my/hn--goto (list :type 'front :feed next :page 0))))

(defun my/hn-select-feed ()
  ":: Pick a listing feed by name and jump to its first page."
  (interactive)
  (let* ((choices (mapcar (lambda (f) (cons (nth 1 f) (car f))) my/hn--feeds))
         (label   (completing-read "HN feed: " choices nil t))
         (id      (cdr (assoc label choices))))
    (when id
      (my/hn--goto (list :type 'front :feed id :page 0)))))

(defun my/hn-clear-cache ()
  ":: Drop every cached page."
  (interactive)
  (clrhash my/hn--cache)
  (message "HN: cache cleared"))

;;; :: Activation (RET / mouse / browser) ------------------------------------

(defun my/hn--btn-title (button)
  ":: Title click: open the external article, or fall back to its comments."
  (let ((url (button-get button 'hn-url))
        (id  (button-get button 'hn-id)))
    (if (and (stringp url) (not (string-empty-p url)))
        (browse-url url)
      (my/hn--goto (list :type 'item :id id)))))

(defun my/hn--btn-comments (button)
  ":: Comments click: load the story's discussion in this buffer."
  (my/hn--goto (list :type 'item :id (button-get button 'hn-id))))

(defun my/hn-activate ()
  ":: RET: follow a link in a comment, else the button at point."
  (interactive)
  (cond ((get-text-property (point) 'shr-url) (shr-browse-url))
        ((button-at (point)) (push-button))
        (t (message "HN: nothing to open here"))))

(defun my/hn-browse-external ()
  ":: Open the current page's article URL in the web browser."
  (interactive)
  (let ((url (or my/hn--page-url my/hn--page-hn-url)))
    (if url (browse-url url) (message "HN: no link for this page"))))

(defun my/hn-browse-comments ()
  ":: Open the current page's HN discussion in the web browser."
  (interactive)
  (if my/hn--page-hn-url
      (browse-url my/hn--page-hn-url)
    (message "HN: no discussion link for this page")))

;;; :: Mode + entry ----------------------------------------------------------

(define-derived-mode my/hn-mode special-mode "HN"
  ":: Major mode for the Hacker News reader buffer."
  (setq-local truncate-lines nil)
  (setq-local line-spacing 0.1)
  (buffer-disable-undo))

(defun my/hn--get-buffer ()
  ":: The singleton *hacker-news* buffer, in `my/hn-mode'."
  (let ((buf (get-buffer-create "*hacker-news*")))
    (with-current-buffer buf
      (unless (derived-mode-p 'my/hn-mode)
        (my/hn-mode)))
    buf))

;;;###autoload
(defun my/hn ()
  ":: Open Hacker News in a dedicated buffer (front page on first launch)."
  (interactive)
  (let ((buf (my/hn--get-buffer)))
    (pop-to-buffer buf)
    (unless my/hn--current
      (my/hn--goto '(:type front :page 0) t))))

;; :: special-mode buffers start in evil *motion* state, where `,' localleader
;; :: is dead -- force normal so the localleader map below works.
(after! evil
  (evil-set-initial-state 'my/hn-mode 'normal))

(map! :leader :desc "Hacker News" "o h" #'my/hn)

(map! :map my/hn-mode-map
      :n "RET"       #'my/hn-activate
      :n [tab]       #'forward-button
      :n [backtab]   #'backward-button
      :n "C-o"       #'my/hn-back
      :n "r"         #'my/hn-reload
      :n "gr"        #'my/hn-reload
      :n "gx"        #'my/hn-browse-external
      :n "]"         #'my/hn-next-page
      :n "["         #'my/hn-prev-page
      :n "gf"        #'my/hn-cycle-feed
      :n "q"         #'quit-window
      :localleader
      :desc "Open article in browser"  "o" #'my/hn-browse-external
      :desc "Open comments in browser" "c" #'my/hn-browse-comments
      :desc "Front page"               "h" #'my/hn-home
      :desc "Reload page"              "r" #'my/hn-reload
      :desc "Next page"                "n" #'my/hn-next-page
      :desc "Previous page"            "p" #'my/hn-prev-page
      :desc "Cycle feed"               "f" #'my/hn-cycle-feed
      :desc "Select feed…"             "F" #'my/hn-select-feed
      :desc "Back"                     "b" #'my/hn-back)
