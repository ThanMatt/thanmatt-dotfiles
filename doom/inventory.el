;;; inventory.el --- Inventory Tracker for Doom Emacs -*- lexical-binding: t; -*-

;; :: Inventory file path
(defvar inventory-file "~/org-notes/inventory.org"
  "Path to the inventory org file.")

(defun inventory/open-or-create ()
  "Open or create the inventory tracker."
  (interactive)
  (let ((filepath (expand-file-name inventory-file))
        (file-exists (file-exists-p (expand-file-name inventory-file))))

    ;; :: Create file if it doesn't exist
    (unless file-exists
      (with-temp-file filepath
        (insert "#+TITLE: Inventory Tracker\n")
        (insert (format "#+DATE: %s\n\n" (format-time-string "%Y-%m-%d")))
        (insert "* Inventory\n\n")
        (insert "| Name | Category | Price Bought | Remarks | Sold |\n")
        (insert "|------+----------+--------------+---------+------|\n")
        (insert "|      |          |              |         | [ ]  |\n")))

    ;; :: Open the file
    (find-file filepath)

    ;; :: Display message
    (if file-exists
        (message "Opened inventory tracker")
      (message "Created new inventory tracker"))))

;; :: Key binding: SPC o i
(map! :leader
      :desc "Open Inventory Tracker"
      "o i" #'inventory/open-or-create)

(provide 'inventory)
;;; inventory.el ends here
