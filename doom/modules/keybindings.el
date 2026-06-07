(map! :leader
      (:prefix ("d" . "dev")

       ;; :: Frontend
       (:prefix ("f" . "frontend")
        :desc "Start dev server"   "s" #'my/frontend-start
        :desc "Stop dev server"    "S" #'my/frontend-stop
        :desc "Build"              "b" #'my/frontend-build
        :desc "Logs"               "l" #'my/frontend-logs
        :desc "Clear logs"         "L" #'my/frontend-logs-clear)

       ;; :: Django / backend
       (:prefix ("d" . "django")
        :desc "Start runserver"    "s" #'my/backend-start
        :desc "Stop runserver"     "S" #'my/backend-stop
        :desc "Logs"               "l" #'my/backend-logs
        :desc "Clear logs"         "L" #'my/backend-logs-clear
        :desc "Management command" "m" #'my/backend-manage)

       ;; :: Workspaces
       (:prefix ("w" . "workspace")
        :desc "Frontend workspace" "f" #'my/workspace-frontend
        :desc "Backend workspace"  "b" #'my/workspace-backend)

       ;; :: Window zoom (tmux-ish: enlargen focus / re-balance)
       :desc "Enlargen window"    "Z" #'doom/window-enlargen
       :desc "Balance windows"    "z" #'balance-windows

       ;; :: Tools
       :desc "Magit status"       "g" #'magit-status
       :desc "Claude Code"        "c" #'my/claude-code
       :desc "Project vterm"      "t" #'my/project-vterm
       :desc "New vterm"          "T" #'my/project-vterm-new
       :desc "Switch vterm"       "v" #'my/vterm-switch
       :desc "Kill vterm"         "k" #'my/vterm-kill
       :desc "Status"             "?" #'my/dev-status))
