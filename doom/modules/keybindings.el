(map! :leader
      (:prefix ("d" . "dev")

               ;; :: Project commands (.dev.el)
               ;; :: NOTE: avoid `r' (reminders), `s' (sql prefix), `c'/`t' etc.
               :desc "Run command"        "d" #'my/project-run
               :desc "Stop server"        "S" #'my/project-stop
               :desc "Logs"               "l" #'my/project-logs
               :desc "Clear logs"         "L" #'my/project-logs-clear
               :desc "Edit .dev.el"       "e" #'my/dev-config-edit

               ;; :: Workspaces
               (:prefix ("w" . "workspace")
                :desc "Frontend workspace" "f" #'my/workspace-frontend
                :desc "Backend workspace"  "b" #'my/workspace-backend)

               ;; :: Window zoom (tmux-ish: enlargen focus / re-balance)
               :desc "Enlargen window"    "Z" #'doom/window-enlargen
               :desc "Balance windows"    "z" #'balance-windows

               ;; :: SQL / DB (read-only Postgres workflow)
               (:prefix ("s" . "sql")
                :desc "Browse DB tables"   "b" #'my/sql-browse
                :desc "Connect to preset"  "c" #'sql-connect
                :desc "Reload connections" "r" #'my/sql-reload-connections
                :desc "SQL scratch buffer" "s" #'my/sql-scratch
                :desc "Run template"       "t" #'my/sql-run-template
                :desc "Preview template"   "T" #'my/sql-preview-template
                :desc "Save query"         "w" #'my/sql-save-query
                :desc "Saved queries"      "q" #'my/sql-run-saved
                :desc "Delete saved query" "d" #'my/sql-delete-saved
                :desc "Kill all DB buffers" "K" #'my/sql-kill-all-buffers)

               ;; :: Tools
               :desc "Toggle TSX engine"  "x" #'my/tsx-toggle-treesit
               ;; :: carry-over daily agenda retired -> denote journal (see backlog.md)
               :desc "Journal (today)"    "a" #'denote-journal-new-or-existing-entry
               :desc "Reminders"          "r" #'my/reminders
               :desc "Magit status"       "g" #'magit-status
               :desc "Claude Code"        "c" #'my/claude-code
               :desc "ncspot (music)"     "m" #'my/ncspot
               :desc "Project vterm"      "t" #'my/project-vterm
               :desc "New vterm"          "T" #'my/project-vterm-new
               :desc "Switch vterm"       "v" #'my/vterm-switch
               :desc "Kill vterm"         "k" #'my/vterm-kill
               :desc "Status"             "?" #'my/dev-status))

