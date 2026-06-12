;;; schema.el -*- lexical-binding: t; -*-

;; :: ============================================================
;; :: API Schema Navigation
;; :: ============================================================
;; :: Pick an endpoint from an OpenAPI TypeScript schema (schema.d.ts) and
;; :: insert an org link to its definition. Point SCHEMA_FILE at your schema
;; :: (e.g. in ~/.config/fish/conf.d/local.fish); defaults to schema.d.ts in the notes dir.

(defvar my/schema-file
  (expand-file-name (or (getenv "SCHEMA_FILE") (expand-file-name "schema.d.ts" my/notes-dir)))
  "Path to the OpenAPI TypeScript schema file.")

(defun my/schema--api-paths ()
  "Extract all API endpoint paths from the schema file."
  (split-string
   (shell-command-to-string
    (format "rg --pcre2 -oN '(?<=    \")[/][^\"]*(?=\": \\{)' %s"
            my/schema-file))
   "\n" t))

(defun my/schema--path-line (path)
  "Return the line number of PATH in the schema file."
  (string-to-number
   (string-trim
    (shell-command-to-string
     (format "rg -n --fixed-strings '    \"%s\"' %s | head -1 | cut -d: -f1"
             path my/schema-file)))))

(defun my/schema-insert-endpoint-link ()
  "Pick an API endpoint and insert an org-mode link at point."
  (interactive)
  (let* ((paths (my/schema--api-paths))
         (selected (completing-read "Endpoint: " paths nil t))
         (line (my/schema--path-line selected))
         (link (format "[[file:%s::%d][%s]]" my/schema-file line selected)))
    (insert link)))

(provide 'schema)
;;; schema.el ends here
