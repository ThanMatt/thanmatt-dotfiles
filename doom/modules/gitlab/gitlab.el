;;; gitlab/gitlab.el --- GitLab integration for Emacs -*- lexical-binding: t; -*-

;; :: ============================================================
;; :: GitLab Integration
;; :: ============================================================
;;
;; :: Setup Instructions:
;; :: 1. Set environment variables in your shell config (~/.zshrc, ~/.bashrc, or ~/.config/fish/config.fish):
;; ::    export GITLAB_URL="https://gitlab.com"  # or your company's GitLab URL
;; ::    export GITLAB_PROJECT_ID="your-project-id"  # find this in GitLab project settings
;; ::    export GITLAB_PROJECT_NAME="project-name"  # short name for your project (e.g., "myapp")
;; ::    # GITLAB_ISSUES_DIR is optional: it applies only in vault flat mode.
;; ::    # With a vault active the issue dir is derived from it -- leave it unset.
;; ::
;; :: 2. Add your GitLab token to ~/.authinfo.gpg:
;; ::    machine gitlab.com login api password YOUR_GITLAB_TOKEN
;; ::
;; :: 3. Reload your Doom config: SPC h r r


;; :: ------------------------------------------------------------
;; :: Files -- split out of the old single modules/gitlab.el
;; :: ------------------------------------------------------------
;; :: Order matters only for TOP-LEVEL forms: the dashboard keymaps call
;; :: `my/gitlab-dash--bind' / `my/gitlab-dash--evil-bind' at load time, so
;; :: dash must precede mrs, issues-dash and pipelines. Everything else is
;; :: plain function calls, resolved at run time.
;; ::
;; ::   core         config, token, JSON, sync + async HTTP, shared helpers
;; ::   issues       issue org files: fetch / lookup / link / refresh / linked MRs
;; ::   todos        todos buffer (SPC o t)
;; ::   mr           create / edit MRs via glab
;; ::   dash         shared dashboard layer
;; ::   mrs          "My MRs" dashboard + single MR view
;; ::   issues-dash  assigned issues dashboard
;; ::   pipelines    pipelines dashboard + watch / poll
;; ::   labels       toggle labels from an issue file
(load! "core")
(load! "issues")
(load! "todos")
(load! "mr")
(load! "dash")
(load! "mrs")
(load! "issues-dash")
(load! "pipelines")
(load! "labels")

;; :: ------------------------------------------------------------
;; :: Leader keys -- every `SPC o' GitLab binding, in one place
;; :: ------------------------------------------------------------
;; :: (Mode-local keymaps stay next to their modes in the files above.)

;; :: Global keybindings for GitLab functions
(map! :leader
      :prefix "o"
      :desc "GitLab Todos" "t" #'my/gitlab-fetch-todos
      :desc "GitLab Fetch Issue" "g i" #'my/gitlab-fetch-issue
      :desc "GitLab Lookup Issue" "g l" #'my/gitlab-lookup-issue
      :desc "GitLab Refresh Issue Index" "g R" #'my/gitlab-refresh-issues-index
      :desc "GitLab Insert Issue Ref" "g c" #'my/gitlab-insert-issue-ref
      :desc "GitLab Refresh Issue" "g r" #'my/gitlab-refresh-issue
      :desc "GitLab Fetch MRs for Issue" "g f" #'my/gitlab-fetch-mr
      :desc "GitLab Merge Requests" "g m" #'my/gitlab-fetch-prs)

;; :: Keybinding for MR creation
(map! :leader
      :prefix "o"
      :desc "GitLab Create MR" "g M" #'my/gitlab-create-mr
      :desc "GitLab Copy MR Link" "g y" #'my/gitlab-copy-mr-link
      :desc "GitLab Edit MR" "g e" #'my/gitlab-edit-mr
      :desc "GitLab Browse Remote" "g b" #'my/gitlab-browse-remote)

(map! :leader
      :prefix "o"
      :desc "GitLab My MRs" "g p" #'my/gitlab-my-merge-requests
      :desc "GitLab My Issues" "g a" #'my/gitlab-my-issues)

(map! :leader
      :prefix "o"
      :desc "GitLab Pipelines" "g P" #'my/gitlab-pipelines)

(map! :leader
      :prefix "o"
      :desc "GitLab Toggle Issue Label" "g L" #'my/gitlab-issue-toggle-label)

(provide 'gitlab)
;;; gitlab.el ends here
