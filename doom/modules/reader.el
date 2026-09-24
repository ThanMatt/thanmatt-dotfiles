;;; modules/reader.el -*- lexical-binding: t; -*-

;; :: Read any web page as org.
;; ::
;; ::   SPC o w          prompt for a URL, open it as an org buffer
;; ::   SPC i w          insert a URL's org conversion at point
;; ::
;; :: In the reader buffer (it is plain `org-mode' + `my/reader-mode'):
;; ::   gr               refetch (busts nothing; there is no cache)
;; ::   gR               toggle readable <-> raw extraction and refetch
;; ::   gx               open the source URL in the external browser
;; ::   gn               save the buffer as a denote note
;; ::   q                bury
;; ::
;; :: Pipeline: curl -> libxml DOM -> strip chrome -> readability -> pandoc.
;; ::
;; :: The readability step is `eww's scorer (Emacs ships it): it walks the DOM
;; :: totting up text-vs-markup density per node and returns the winning
;; :: subtree. That is a heuristic, so it *will* mispick on pages that are not
;; :: semantically friendly -- a wrapper div of teasers can outscore the article,
;; :: and anything rendered client-side arrives as an empty shell no extractor
;; :: can rescue. Two guards make that survivable rather than fatal:
;; ::
;; ::   1. if the winning subtree keeps less than `my/reader-readable-min-ratio'
;; ::      of the page's text, the extraction is rejected and the whole body is
;; ::      converted instead -- noisier, but never empty;
;; ::   2. `gR' (or a C-u prefix on the command) forces raw mode by hand, for
;; ::      when the guard's judgement and yours differ.
;; ::
;; :: Requires `pandoc' on PATH (already a dependency of modules/gitlab/).

(require 'cl-lib)
(require 'dom)
(require 'shr)
(require 'eww)
(require 'url-parse)
(require 'url-expand)

;;; :: Options ---------------------------------------------------------------

(defvar my/reader-user-agent
  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
  ":: UA sent with the fetch. A bare curl UA gets 403'd by a lot of CDNs.")

(defvar my/reader-timeout 25
  ":: Seconds before the fetch is abandoned.")

(defvar my/reader-readable-min-ratio 0.10
  ":: Reject the readability pick if it retains less than this fraction of the
page's text, and fall back to the full body. Guards against a scorer that
latched onto a sidebar on a page with no article-shaped markup.")

(defvar my/reader-strip-tags
  '(script style noscript iframe svg canvas form button input select textarea
    template link meta title)
  ":: Tags removed from every page, readable or raw. Non-content in all cases.
`title' is in the list because the page title is read off the DOM *before* the
strip, and left in place it would render as a stray line of body text.")

(defvar my/reader-strip-class-regex
  (concat "\\`\\(?:mw-editsection\\|navbox\\|cookie\\|consent\\|advert"
          "\\|share-\\|social-\\|newsletter\\|subscribe\\|breadcrumb"
          "\\|skip-link\\|screen-reader\\|visually-hidden\\|sr-only\\)")
  ":: Nodes whose class or id has a token matching this are dropped in readable
mode. Anchored per class token, so `sr-only' matches but a token
like `commentary' does not. Keep it conservative: a class prefix that looks
like chrome can also name the content wrapper (Wikipedia's article body is a
`vector-body' div), and over-stripping happens before the ratio guard runs, so
it is invisible to that safety net. Set to nil to disable.")

(defvar my/reader-strip-chrome-tags '(nav footer aside)
  ":: Additionally removed in readable mode: site chrome that survives scoring
often enough to be worth pre-empting. Kept in raw mode.")

(defvar my/reader-fake-langs
  '("highlight" "highlighter-rouge" "sourcecode" "code" "pre" "prettyprint"
    "notranslate" "hljs" "syntax")
  ":: Class names pandoc mistakes for a src-block language. Rewritten to `text'.")

;;; :: Buffer state ----------------------------------------------------------

(defvar-local my/reader--url nil ":: Source URL of this reader buffer.")
(defvar-local my/reader--raw nil ":: Non-nil if extraction skipped readability.")
(defvar-local my/reader--title nil ":: Page title, for denote export.")

;;; :: Fetch -----------------------------------------------------------------

(defun my/reader--decode (bytes)
  ":: Decode raw BYTES using the charset declared in the markup, else utf-8."
  (let* ((head (substring bytes 0 (min 4096 (length bytes))))
         (cs (and (string-match "charset=[\"']?\\([A-Za-z0-9_-]+\\)" head)
                  (intern (downcase (match-string 1 head)))))
         (coding (if (and cs (coding-system-p cs)) cs 'utf-8)))
    (decode-coding-string bytes coding)))

(defun my/reader--fetch (url callback)
  ":: GET URL asynchronously; call CALLBACK with the decoded body string.
Errors are reported to the echo area and CALLBACK is not run."
  (unless (executable-find "curl")
    (user-error "reader: curl not found on PATH"))
  (let ((buf (generate-new-buffer " *reader-curl*")))
    (make-process
     :name "reader-curl"
     :buffer buf
     :noquery t
     :coding 'binary
     :command (list "curl" "-sSL" "--compressed"
                    "--max-time" (number-to-string my/reader-timeout)
                    "-A" my/reader-user-agent
                    url)
     :sentinel
     (lambda (proc _event)
       (when (memq (process-status proc) '(exit signal))
         (let ((code (process-exit-status proc))
               (body (with-current-buffer buf (buffer-string))))
           (kill-buffer buf)
           (cond
            ((/= code 0)
             (message "reader: fetch failed (curl %d) %s" code (string-trim body)))
            ((string-prefix-p "%PDF" body)
             (message "reader: %s is a PDF, not a web page" url))
            ((string-empty-p (string-trim body))
             (message "reader: %s returned an empty body" url))
            (t (funcall callback (my/reader--decode body))))))))))

;;; :: DOM shaping -----------------------------------------------------------

(defun my/reader--parse (html)
  ":: Parse HTML into a DOM."
  (with-temp-buffer
    (insert html)
    (libxml-parse-html-region (point-min) (point-max))))

(defun my/reader--strip-noise (dom)
  ":: Drop nodes whose class/id token matches `my/reader-strip-class-regex'.
Cheap chrome removal for the things readability reliably keeps: wiki
edit-section links, cookie banners, share rails, screen-reader-only text."
  (when my/reader-strip-class-regex
    (dolist (node (dom-search
                   dom
                   (lambda (n)
                     (and (consp n)
                          (cl-some (lambda (tok)
                                     (string-match-p my/reader-strip-class-regex tok))
                                   (split-string (concat (or (dom-attr n 'class) "") " "
                                                         (or (dom-attr n 'id) ""))
                                                 "[ \t\n]+" t)))))
                  dom)
      (ignore-errors (dom-remove-node dom node))))
  dom)

(defun my/reader--strip (dom tags)
  ":: Remove every node in DOM whose tag is in TAGS. Returns DOM."
  (dolist (tag tags dom)
    (dolist (node (dom-by-tag dom tag))
      (ignore-errors (dom-remove-node dom node)))))

(defun my/reader--absolutize (dom base)
  ":: Rewrite relative href/src attributes in DOM against BASE, so links and
images still resolve once the page is out of its own origin."
  (dolist (node (dom-search dom (lambda (n) (and (consp n) (dom-attributes n)))) dom)
    (dolist (attr '(href src))
      (let ((val (dom-attr node attr)))
        (when (and (stringp val)
                   (not (string-empty-p val))
                   (not (string-match-p "\\`\\(?:[a-z+.-]+:\\|#\\|//\\)" val)))
          (dom-set-attribute node attr
                             (condition-case nil
                                 (url-expand-file-name val base)
                               (error val))))))))

(defun my/reader--title-of (dom url)
  ":: Best available title for the page: og:title, <title>, first <h1>, host."
  (or (cl-loop for m in (dom-by-tag dom 'meta)
               when (member (or (dom-attr m 'property) (dom-attr m 'name))
                            '("og:title" "twitter:title"))
               return (dom-attr m 'content))
      (let ((tt (car (dom-by-tag dom 'title))))
        (and tt (string-trim (dom-texts tt))))
      (let ((h1 (car (dom-by-tag dom 'h1))))
        (and h1 (string-trim (dom-texts h1))))
      (url-host (url-generic-parse-url url))
      url))

(defun my/reader--extract (dom raw)
  ":: Return the DOM subtree to convert.
With RAW non-nil, that is the whole body. Otherwise run `eww's readability
scorer and accept its pick only if it keeps a credible share of the text --
see `my/reader-readable-min-ratio'."
  (let ((body (or (car (dom-by-tag dom 'body)) dom)))
    (if raw
        body
      (my/reader--strip body my/reader-strip-chrome-tags)
      (my/reader--strip-noise body)
      (let* ((total (length (dom-texts body)))
             (best (ignore-errors
                     (eww-score-readability body)
                     (eww-highest-readability body)))
             (kept (and best (length (dom-texts best)))))
        (if (and best (> total 0) (>= (/ (float kept) total)
                                      my/reader-readable-min-ratio))
            best
          (message "reader: readability pick looked thin -- using the full page")
          body)))))

;;; :: HTML -> org -----------------------------------------------------------

(defun my/reader--fragment-html (node)
  ":: Serialize NODE as a standalone HTML document for pandoc.
Structural roots are re-tagged as a plain <div> first: readability can legally
return <head> on a page whose markup put the content there (libxml is lenient
about a missing <body>), and pandoc reads anything inside <head> as document
metadata -- i.e. throws the whole article away."
  (let ((node (if (memq (dom-tag node) '(html head body))
                  (apply #'dom-node 'div nil (dom-children node))
                node)))
    (concat "<html><body>" (shr-dom-to-xml node) "</body></html>")))

(defun my/reader--pandoc (html)
  ":: Convert an HTML string to org via pandoc.
`-native_divs'/`-native_spans' stop pandoc wrapping every wrapper <div> in an
org special block, which is most of the noise in a naive conversion."
  (unless (executable-find "pandoc")
    (user-error "reader: pandoc not found on PATH"))
  (with-temp-buffer
    (insert html)
    (let ((status (call-process-region
                   (point-min) (point-max) "pandoc" t t nil
                   "-f" "html-native_divs-native_spans"
                   "-t" "org" "--wrap=none")))
      (unless (eq status 0)
        (user-error "reader: pandoc failed: %s" (string-trim (buffer-string))))
      (buffer-string))))

(defun my/reader--in-block-p (state)
  ":: Fold the current line into STATE, a bool tracking #+begin_/#+end_ nesting.
Returns the new state; call with point at the start of the line."
  (cond ((looking-at-p "[ \t]*#\\+begin_") t)
        ((looking-at-p "[ \t]*#\\+end_") nil)
        (t state)))

(defun my/reader--normalize (org base-level)
  ":: Tidy pandoc's org output and rebase its headings at BASE-LEVEL.
Drops the :PROPERTIES: drawers pandoc emits for anchor ids, repairs src-block
languages it inferred from styling classes, and collapses blank runs. All of it
is block-aware so nothing inside a src block is rewritten."
  (with-temp-buffer
    (insert org)
    ;; :: 1. anchor-id property drawers
    (goto-char (point-min))
    (while (re-search-forward "^[ \t]*:PROPERTIES:\n\\(?:[ \t]*:CUSTOM_ID:[^\n]*\n\\)+[ \t]*:END:\n?" nil t)
      (replace-match ""))
    ;; :: 2. styling classes mistaken for languages
    (goto-char (point-min))
    (while (re-search-forward "^[ \t]*#\\+begin_src[ \t]+\\([^ \t\n]+\\)" nil t)
      (let ((lang (downcase (match-string 1))))
        (cond ((string-prefix-p "language-" lang)
               (replace-match (substring lang 9) t t nil 1))
              ((member lang my/reader-fake-langs)
               (replace-match "text" t t nil 1)))))
    ;; :: 3. rebase headings (shallowest heading becomes BASE-LEVEL)
    (let ((min-level nil) (in-block nil))
      (goto-char (point-min))
      (while (not (eobp))
        (beginning-of-line)
        (setq in-block (my/reader--in-block-p in-block))
        (when (and (not in-block) (looking-at "\\(\\*+\\) "))
          (setq min-level (min (or min-level 99) (length (match-string 1)))))
        (forward-line 1))
      (when (and min-level (/= min-level base-level))
        (let ((delta (- base-level min-level)) (in-block nil))
          (goto-char (point-min))
          (while (not (eobp))
            (beginning-of-line)
            (setq in-block (my/reader--in-block-p in-block))
            (when (and (not in-block) (looking-at "\\(\\*+\\) "))
              (let ((lvl (max 1 (+ (length (match-string 1)) delta))))
                (replace-match (make-string lvl ?*) t t nil 1)))
            (forward-line 1)))))
    ;; :: 4. blank runs
    (goto-char (point-min))
    (while (re-search-forward "\n\\{3,\\}" nil t)
      (replace-match "\n\n"))
    (string-trim (buffer-string))))

(defun my/reader--convert (html url raw base-level)
  ":: Full pipeline. Returns (TITLE . ORG-STRING) for HTML fetched from URL."
  (let* ((dom (my/reader--parse html))
         (title (my/reader--title-of dom url)))
    (my/reader--strip dom my/reader-strip-tags)
    (my/reader--absolutize dom url)
    (let* ((subtree (my/reader--extract dom raw))
           (clean (my/reader--fragment-html subtree)))
      (cons title (my/reader--normalize (my/reader--pandoc clean) base-level)))))

;;; :: Reader buffer ---------------------------------------------------------

(defun my/reader--empty-p (org url)
  ":: Non-nil (having said so) when the conversion produced no text at all.
Almost always means the page ships an empty shell and paints itself with
JavaScript, which no HTML-level extractor can do anything about. Reported
rather than signalled: this runs inside a process sentinel, where an error
surfaces as `error in process sentinel' noise instead of the actual reason."
  (when (string-empty-p (string-trim org))
    (message "reader: no text in %s -- the page is likely rendered client-side (JS)" url)
    t))

(defun my/reader--header (title url raw)
  ":: Org front matter for a reader buffer."
  (format "#+title: %s\n#+source: %s\n#+created: %s\n#+filetags: :web:\n%s\n"
          title url
          (format-time-string "[%Y-%m-%d %a %H:%M]")
          (if raw "#+extraction: raw (full page)\n" "")))

(defun my/reader--render (url raw &optional buffer)
  ":: Fetch URL and (re)fill BUFFER, or a fresh one, with its org conversion."
  (message "reader: fetching %s…" url)
  (my/reader--fetch
   url
   (lambda (html)
     (let* ((pair (my/reader--convert html url raw 1))
            (title (car pair))
            (body (cdr pair)))
       (unless (my/reader--empty-p body url)
         (my/reader--fill (or (and (buffer-live-p buffer) buffer)
                              (generate-new-buffer (format "*web: %s*" title)))
                          title body url raw))))))

(defun my/reader--fill (buf title body url raw)
  ":: Put the converted page into BUF and show it."
  (with-current-buffer buf
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert (my/reader--header title url raw) "\n" body "\n"))
    (goto-char (point-min))
    (unless (derived-mode-p 'org-mode) (org-mode))
    (my/reader-mode 1)
    (setq my/reader--url url
          my/reader--raw raw
          my/reader--title title)
    (rename-buffer (format "*web: %s*" title) t)
    (set-buffer-modified-p nil)
    (org-set-startup-visibility))
  (pop-to-buffer buf)
  (message "reader: %s" title))

;;;###autoload
(defun my/web-to-org (url &optional raw)
  ":: Fetch URL and open it as org in a reader buffer.
With a prefix argument, skip readability extraction and convert the whole page
(RAW) -- use it when the heuristic drops content you wanted."
  (interactive (list (my/reader--read-url "Web page → org: ")
                     current-prefix-arg))
  (my/reader--render url (and raw t)))

;;;###autoload
(defun my/web-to-org-insert (url &optional raw)
  ":: Insert URL's org conversion at point, rebased under the current heading."
  (interactive (list (my/reader--read-url "Insert web page as org: ")
                     current-prefix-arg))
  (let ((target (current-buffer))
        (pos (point))
        (level (if (derived-mode-p 'org-mode)
                   (save-excursion
                     (if (org-before-first-heading-p) 1
                       (1+ (org-current-level))))
                 1)))
    (message "reader: fetching %s…" url)
    (my/reader--fetch
     url
     (lambda (html)
       (let* ((pair (my/reader--convert html url (and raw t) level))
              (title (car pair)))
         (unless (my/reader--empty-p (cdr pair) url)
           (with-current-buffer target
             (save-excursion
               (goto-char pos)
               (insert (format "%s %s\n:PROPERTIES:\n:SOURCE: %s\n:END:\n\n%s\n"
                               (make-string level ?*) title url (cdr pair)))))
           (message "reader: inserted %s" title)))))))

(defun my/reader--read-url (prompt)
  ":: Prompt for a URL, defaulting to the most plausible one to hand:
point, the org link at point, the current eww page, then the kill ring."
  (let* ((default (or (thing-at-point 'url t)
                      (and (derived-mode-p 'org-mode)
                           (let ((ctx (org-element-context)))
                             (and (eq (org-element-type ctx) 'link)
                                  (string-match-p "\\`https?\\'"
                                                  (or (org-element-property :type ctx) ""))
                                  (org-element-property :raw-link ctx))))
                      (bound-and-true-p eww-current-url)
                      (let ((kill (ignore-errors (current-kill 0 t))))
                        (and (stringp kill)
                             (string-match-p "\\`https?://[^[:space:]]+\\'"
                                             (string-trim kill))
                             (string-trim kill)))))
         (url (string-trim
               (read-string (if default (format "%s(%s) " prompt default) prompt)
                            nil nil default))))
    (when (string-empty-p url) (user-error "reader: no URL given"))
    (if (string-match-p "\\`[a-z+.-]+:" url) url (concat "https://" url))))

;;; :: Reader buffer commands ------------------------------------------------

(defun my/reader-refresh ()
  ":: Refetch the current reader buffer."
  (interactive)
  (unless my/reader--url (user-error "Not a reader buffer"))
  (my/reader--render my/reader--url my/reader--raw (current-buffer)))

(defun my/reader-toggle-raw ()
  ":: Flip between readability-extracted and whole-page conversion, and refetch."
  (interactive)
  (unless my/reader--url (user-error "Not a reader buffer"))
  (my/reader--render my/reader--url (not my/reader--raw) (current-buffer)))

(defun my/reader-browse-external ()
  ":: Open the source URL in the external browser."
  (interactive)
  (unless my/reader--url (user-error "Not a reader buffer"))
  (browse-url my/reader--url))

(defun my/reader-to-denote ()
  ":: Save the current reader buffer as a denote note tagged `web'."
  (interactive)
  (unless my/reader--url (user-error "Not a reader buffer"))
  (unless (fboundp 'denote) (user-error "reader: denote is not available"))
  (let* ((title (read-string "Note title: " my/reader--title))
         (body (save-excursion
                 (goto-char (point-min))
                 ;; :: skip our own front matter -- denote writes its own
                 (while (and (not (eobp)) (looking-at-p "^#\\+\\|^[ \t]*$"))
                   (forward-line 1))
                 (buffer-substring-no-properties (point) (point-max)))))
    (denote title '("web") 'org)
    (goto-char (point-max))
    (insert (format "\nSource: %s\n\n%s\n" my/reader--url body))
    (save-buffer)
    (message "reader: saved as %s" (buffer-name))))

;;; :: Mode + keys -----------------------------------------------------------

(defvar my/reader-mode-map (make-sparse-keymap)
  ":: Keymap for `my/reader-mode'.")

(define-minor-mode my/reader-mode
  ":: Minor mode layered over `org-mode' in web reader buffers."
  :lighter " Reader"
  :keymap my/reader-mode-map)

(map! :leader
      :desc "Web page → org"   "o w" #'my/web-to-org
      :desc "Web page as org"  "i w" #'my/web-to-org-insert)

;; :: `g'-prefixed only, deliberately: a `:localleader' block here would live in
;; :: a *minor* mode map and so shadow org-mode's own `,' menu wholesale.
(map! :map my/reader-mode-map
      :n "gr" #'my/reader-refresh
      :n "gR" #'my/reader-toggle-raw
      :n "gx" #'my/reader-browse-external
      :n "gn" #'my/reader-to-denote
      :n "q"  #'bury-buffer)

(provide 'reader)
;;; reader.el ends here
