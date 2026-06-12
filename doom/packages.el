;; -*- no-byte-compile: t; -*-
;;; $DOOMDIR/packages.el

;; :: web-mode for .tsx/.jsx without tree-sitter (libtree-sitter 0.26 vs Emacs
;; :: 30.2 breaks the tsx grammar's predicate queries). See config.el.
(package! web-mode)

;; :: vtsls under lsp-mode -- wraps VS Code's TS engine; handles Vite solution-
;; :: style tsconfigs that the built-in ts-ls (typescript-language-server) gets
;; :: wrong. Registers at :priority -1, beating ts-ls (-2), so it's auto-chosen.
(package! lsp-vtsls :recipe (:host github :repo "sdvcrx/lsp-vtsls"))

;; :: tailwindcss-language-server client for lsp-mode. (Upstream lsp-mode merged
;; :: a built-in client on master, but Doom pins lsp-mode 9.0.1, which predates
;; :: it -- so the external package is still required here.) Run as an add-on so
;; :: it coexists with vtsls; see config.el.
(package! lsp-tailwindcss :recipe (:host github :repo "merrickluo/lsp-tailwindcss"))

;; To install a package with Doom you must declare them here and run 'doom sync'
;; on the command line, then restart Emacs for the changes to take effect -- or


;; To install SOME-PACKAGE from MELPA, ELPA or emacsmirror:
;; (package! some-package)

;; To install a package directly from a remote git repo, you must specify a
;; `:recipe'. You'll find documentation on what `:recipe' accepts here:
;; https://github.com/radian-software/straight.el#the-recipe-format
;; (package! another-package
;;   :recipe (:host github :repo "username/repo"))

;; If the package you are trying to install does not contain a PACKAGENAME.el
;; file, or is located in a subdirectory of the repo, you'll need to specify
;; `:files' in the `:recipe':
;; (package! this-package
;;   :recipe (:host github :repo "username/repo"
;;            :files ("some-file.el" "src/lisp/*.el")))

;; If you'd like to disable a package included with Doom, you can do so here
;; with the `:disable' property:
;; (package! builtin-package :disable t)

;; You can override the recipe of a built in package without having to specify
;; all the properties for `:recipe'. These will inherit the rest of its recipe
;; from Doom or MELPA/ELPA/Emacsmirror:
;; (package! builtin-package :recipe (:nonrecursive t))
;; (package! builtin-package-2 :recipe (:repo "myfork/package"))

;; Specify a `:branch' to install a package from a particular branch or tag.
;; This is required for some packages whose default branch isn't 'master' (which
;; our package manager can't deal with; see radian-software/straight.el#279)
;; (package! builtin-package :recipe (:branch "develop"))

;; Use `:pin' to specify a particular commit to install.
;; (package! builtin-package :pin "1a2b3c4d5e")


;; Doom's packages are pinned to a specific commit and updated from release to
;; release. The `unpin!' macro allows you to unpin single packages...
;; (unpin! pinned-package)
;; ...or multiple packages
;; (unpin! pinned-package another-pinned-package)
;; ...Or *all* packages (NOT RECOMMENDED; will likely break things)
;; (unpin! t)
;;
