;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; Place your private configuration here! Remember, you do not need to run 'doom
;; sync' after modifying this file!


;; Some functionality uses this to identify you, e.g. GPG configuration, email
;; clients, file templates and snippets. It is optional.
;; (setq user-full-name "John Doe"
;;       user-mail-address "john@doe.com")

;; Doom exposes five (optional) variables for controlling fonts in Doom:
;;
;; - `doom-font' -- the primary font to use
;; - `doom-variable-pitch-font' -- a non-monospace font (where applicable)
;; - `doom-big-font' -- used for `doom-big-font-mode'; use this for
;;   presentations or streaming.
;; - `doom-symbol-font' -- for symbols
;; - `doom-serif-font' -- for the `fixed-pitch-serif' face
;;
;; See 'C-h v doom-font' for documentation and more examples of what they
;; accept. For example:
;;
;;(setq doom-font (font-spec :family "Fira Code" :size 12 :weight 'semi-light)
;;      doom-variable-pitch-font (font-spec :family "Fira Sans" :size 13))
;;
;; If you or Emacs can't find your font, use 'M-x describe-font' to look them
;; up, `M-x eval-region' to execute elisp code, and 'M-x doom/reload-font' to
;; refresh your font settings. If Emacs still can't find your font, it likely
;; wasn't installed correctly. Font issues are rarely Doom issues!

;; There are two ways to load a theme. Both assume the theme is installed and
;; available. You can either set `doom-theme' or manually load a theme with the
;; `load-theme' function. This is the default:
(setq doom-theme 'doom-one)

;; This determines the style of line numbers in effect. If set to `nil', line
;; numbers are disabled. For relative line numbers, set this to `relative'.
(setq display-line-numbers-type 'relative)

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/notes/")


;; Whenever you reconfigure a package, make sure to wrap your config in an
;; `after!' block, otherwise Doom's defaults may override your settings. E.g.
;;
;;   (after! PACKAGE
;;     (setq x y))
;;
;; The exceptions to this rule:
;;
;;   - Setting file/directory variables (like `org-directory')
;;   - Setting variables which explicitly tell you to set them before their
;;     package is loaded (see 'C-h v VARIABLE' to look up their documentation).
;;   - Setting doom variables (which start with 'doom-' or '+').
;;
;; Here are some additional functions/macros that will help you configure Doom.
;;
;; - `load!' for loading external *.el files relative to this one
;; - `use-package!' for configuring packages
;; - `after!' for running code after a package has loaded
;; - `add-load-path!' for adding directories to the `load-path', relative to
;;   this file. Emacs searches the `load-path' when you load packages with
;;   `require' or `use-package'.
;; - `map!' for binding new keys
;;
;; To get information about any of these functions/macros, move the cursor over
;; the highlighted symbol at press 'K' (non-evil users must press 'C-c c k').
;; This will open documentation for it, including demos of how they are used.
;; Alternatively, use `C-h o' to look up a symbol (functions, variables, faces,
;; etc).
;;
;; You can also try 'gd' (or 'C-c c d') to jump to their definition and see how
;; they are implemented.
;; Use bash for internal Emacs processes
(setq shell-file-name (executable-find "bash"))

;; But keep Fish for terminal emulators within Emacs
(setq-default vterm-shell "/opt/homebrew/bin/fish")
(setq-default explicit-shell-file-name "/opt/homebrew/bin/fish")

;; Set the default font
(setq doom-font (font-spec :family "FiraCode Nerd Font" :size 12)
      doom-variable-pitch-font (font-spec :family "FiraCode Nerd Font" :size 14))

;; Optional: Set bigger font for headings in org-mode
(setq doom-big-font (font-spec :family "FiraCode Nerd Font" :size 18))

(defun my/create-project (project-name)
  "Create a new project structure with template files."
  (interactive "sProject name: ")
  (let ((project-dir (expand-file-name 
                      (concat "~/notes/projects/" project-name))))
    ;; Create directory
    (make-directory project-dir t)
    ;; Create project.org with template
    (with-temp-file (concat project-dir "/project.org")
      (insert (format "#+TITLE: %s\n#+AUTHOR: Your Name\n#+DATE: %s\n\n* Overview\n\n* Goals\n- [ ] \n\n* Tasks\n** TODO \n\n* Resources\n\n* Notes\n"
                      project-name 
                      (format-time-string "%Y-%m-%d"))))
    ;; Open the new project file
    (find-file (concat project-dir "/project.org"))))

(setq org-export-show-temporary-export-buffer nil)
(defun my/org-export-html-open ()
  (interactive)
  (org-html-export-to-html)
  (browse-url (concat "file://" (expand-file-name (org-export-output-file-name ".html")))))
(global-set-key (kbd "C-c e h") #'my/org-export-html-open)


(org-babel-do-load-languages
 'org-babel-load-languages
 '((emacs-lisp . t)
   (python     . t)
   (shell      . t)
   (js         . t)))   ;; <- this enables JavaScript


(setq +doom-dashboard-ascii-banner-fn #'my/simple-banner)

(defun my/simple-banner ()
  '("                                    "
    "    Welcome to My Emacs Setup!     "
    "                                    "
    "         Ready to code...           "
    "                                    "))

; (set-frame-parameter nil 'internal-border-width 0)
;; Remove title bar (gives you more screen space)
; (add-to-list 'default-frame-alist '(undecorated . t))

; ;; Optional: Also remove the menu bar if you want
(menu-bar-mode -1)
;;
;; This gives you a minimal title bar
(add-to-list 'default-frame-alist '(ns-transparent-titlebar . t))
(add-to-list 'default-frame-alist '(ns-appearance . dark)) ; or 'light

(setq org-image-actual-width '(400))

(setq org-agenda-files '("~/notes/notes.org"
                         "~/notes/projects/"))

;; Toggle vterm in a popup window
(map! "C-c t" #'+vterm/toggle)
