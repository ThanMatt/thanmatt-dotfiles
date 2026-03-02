;;; finance.el --- Personal Finance Tracker for Doom Emacs -*- lexical-binding: t; -*-

;; :: Finance directory configuration
(defvar finance-directory "~/org-notes/finance/"
  "Directory where finance org files are stored.")

;; :: Ensure finance directory exists
(unless (file-exists-p finance-directory)
  (make-directory finance-directory t))

(defun finance/create-expense-tracker ()
  "Create or open the expense tracker for the current month."
  (interactive)
  (let* ((current-date (decode-time))
         (month (format "%02d" (nth 4 current-date)))
         (year (format "%d" (nth 5 current-date)))
         (filename (format "%s-%s.org" month year))
         (filepath (expand-file-name filename finance-directory))
         (month-name (format-time-string "%B"))
         (file-exists (file-exists-p filepath)))

    ;; :: Create file if it doesn't exist
    (unless file-exists
      (with-temp-file filepath
        (insert (format "#+TITLE: Expense Tracker - %s %s\n" month-name year))
        (insert (format "#+DATE: %s-%s\n\n" year month))
        (insert "* Starting Balance\n")
        (insert "₱0.00\n\n")
        (insert "* Budget\n\n")
        (insert "| Category     | Budget |\n")
        (insert "|--------------+--------|\n")
        (insert "| Food         |   0.00 |\n")
        (insert "| Transport    |   0.00 |\n")
        (insert "| Utilities    |   0.00 |\n")
        (insert "| Entertainment|   0.00 |\n")
        (insert "| Other        |   0.00 |\n\n")
        (insert "#+BEGIN_SRC emacs-lisp :exports results :results raw\n")
        (insert "(finance/calculate-total-budget)\n")
        (insert "#+END_SRC\n\n")
        (insert "* Transactions\n\n")
        (insert "| Transaction Name | Type    | Category | Amount |\n")
        (insert "|------------------+---------+----------+--------|\n")
        (insert "|                  |         |          |        |\n")
        (insert "#+TBLFM: \n\n")
        (insert "* Summary\n\n")
        (insert "#+BEGIN_SRC emacs-lisp :exports results :results raw\n")
        (insert "(finance/calculate-balance)\n")
        (insert "#+END_SRC\n")))

    ;; :: Open the file
    (find-file filepath)

    ;; :: Display message
    (if file-exists
        (message "Opened existing expense tracker for %s %s" month-name year)
      (message "Created new expense tracker for %s %s" month-name year))))

(defun finance/calculate-total-budget ()
  "Calculate the total budget from the budget table."
  (save-excursion
    (goto-char (point-min))
    (let ((total-budget 0.00))

      ;; :: Parse budget table
      (when (re-search-forward "^| Category" nil t)
        (forward-line 2) ;; :: Skip header and separator
        (while (looking-at "^|\\s-*\\([^|]+\\)\\s-*|\\s-*\\([0-9.]+\\)")
          (let ((budget (string-to-number (match-string 2))))
            (setq total-budget (+ total-budget budget)))
          (forward-line 1)))

      (format "*Total Budget: ₱%.2f*" total-budget))))

(defun finance/calculate-balance ()
  "Calculate the current balance and budget status from tables."
  (save-excursion
    (goto-char (point-min))
    (let ((starting-balance 0.00)
          (total-income 0.00)
          (total-expense 0.00)
          (budget-table (make-hash-table :test 'equal))
          (spending-table (make-hash-table :test 'equal)))

      ;; :: Parse starting balance
      (when (re-search-forward "\\* Starting Balance\n₱\\([0-9.]+\\)" nil t)
        (setq starting-balance (string-to-number (match-string 1))))

      ;; :: Parse budget table
      (goto-char (point-min))
      (when (re-search-forward "^| Category" nil t)
        (forward-line 2) ;; :: Skip header and separator
        (while (looking-at "^|\\s-*\\([^|]+\\)\\s-*|\\s-*\\([0-9.]+\\)")
          (let ((category (string-trim (match-string 1)))
                (budget (string-to-number (match-string 2))))
            (when (not (string-empty-p category))
              (puthash category budget budget-table)))
          (forward-line 1)))

      ;; :: Parse transactions table
      (goto-char (point-min))
      (when (re-search-forward "^| Transaction Name" nil t)
        (forward-line 2) ;; :: Skip header and separator
        (while (looking-at "^|\\s-*\\([^|]+\\)\\s-*|\\s-*\\([^|]+\\)\\s-*|\\s-*\\([^|]+\\)\\s-*|\\s-*[₱$]?\\([0-9.]+\\)")
          (let ((transaction-name (string-trim (match-string 1)))
                (type (string-trim (match-string 2)))
                (category (string-trim (match-string 3)))
                (amount (string-to-number (match-string 4))))
            (when (and (not (string-empty-p transaction-name))
                       (> amount 0))
              (cond
               ((string-match-p "income" (downcase type))
                (setq total-income (+ total-income amount)))
               ((string-match-p "expense" (downcase type))
                (setq total-expense (+ total-expense amount))
                ;; :: Track spending by category
                (when (not (string-empty-p category))
                  (puthash category
                           (+ (gethash category spending-table 0.00) amount)
                           spending-table))))))
          (forward-line 1)))

      ;; :: Calculate current balance
      (let ((current-balance (+ starting-balance total-income (- total-expense)))
            (result ""))
        (setq result (format "** Balance Overview\n- Starting Balance: ₱%.2f\n- Total Income: ₱%.2f\n- Total Expenses: ₱%.2f\n- *Current Balance: ₱%.2f*\n\n"
                             starting-balance total-income total-expense current-balance))

        ;; :: Add budget breakdown
        (setq result (concat result "** Budget Status\n\n"))
        (setq result (concat result "| Category | Budget | Spent | Remaining |\n"))
        (setq result (concat result "|----------+--------+-------+-----------|\n"))

        (maphash (lambda (category budget)
                   (let* ((spent (gethash category spending-table 0.00))
                          (remaining (- budget spent)))
                     (setq result (concat result
                                          (format "| %s | ₱%.2f | ₱%.2f | ₱%.2f |\n"
                                                  category budget spent remaining)))))
                 budget-table)

        result))))

;; :: Key binding: SPC o e x
(map! :leader
      :desc "Open Expense Tracker"
      "o e x" #'finance/create-expense-tracker)

(provide 'finance)
;;; finance.el ends here
