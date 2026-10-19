;;; parts/sql.el -*- lexical-binding: t; -*-

(after! sql
  (defun zz/insert-on-psql ()
    (interactive)
    (evil-goto-line)
    (evil-append-line 1))
  (map! :mode sql-interactive :map sql-interactive-mode-map
        :n "q" #'zz/insert-on-psql
        :n "i" #'zz/insert-on-psql
        :prefix "C-c" :desc "Execute SQL query" :im "C-c" #'sql-send-paragraph
        :localleader :desc "Execute SQL query" :m "x" #'sql-send-paragraph)
  (map! :localleader :prefix "l"
        :desc "Describe table" :nv "t" #'sql-list-table
        :desc "List tables" :nv "a" #'sql-list-all))

(add-hook! sql-mode
  (set-formatter!
    'sqlfluff
    '("sqlfluff" "format"
      "--processes" "0" "--disable-progress-bar" "--stdin-filename" "--nocolor"
      "-")
    :modes '(sql-mode)))
