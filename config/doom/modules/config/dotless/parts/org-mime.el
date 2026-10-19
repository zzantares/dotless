;;; parts/org-mime.el -*- lexical-binding: t; -*-

(after! org-mime
  (setq org-mime-export-options
        '(:section-numbers nil
          :with-author nil
          :with-toc nil)))
