;;; parts/claude-code-ide.el -*- lexical-binding: t; -*-

(after! claude-code-ide
  (setq claude-code-ide-window-side 'right
        claude-code-ide-window-width 90)

  (defun my/claude-tutor-feedback ()
    "Ask Claude Code for Socratic feedback on the current file."
    (interactive)
    (claude-code-ide-send-prompt
     (format "I'm working on %s — Socratic feedback only. Point at problems and ask guiding questions. Do not write code or give away answers."
             (buffer-file-name))))

  (map! :leader :prefix "l" :desc "Tutor feedback" :nv "T" #'my/claude-tutor-feedback)

  (claude-code-ide-emacs-tools-setup))
