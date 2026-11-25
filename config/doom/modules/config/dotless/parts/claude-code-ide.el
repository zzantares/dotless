;;; parts/claude-code-ide.el -*- lexical-binding: t; -*-

(after! claude-code-ide
  (setq claude-code-ide-window-side 'right
        claude-code-ide-window-width 90
        ;; vterm and eat both corrupt the TUI: scroll jumps that grow with the
        ;; session (upstream #181, #171) and a prompt that drifts off the cursor
        ;; because reflow is cached per selected frame (#197).
        claude-code-ide-terminal-backend 'ghostel
        ;; ESC edits the prompt in normal state; C-c C-r sends it to Claude.
        claude-code-ide-ghostel-evil-escape 'evil)

  ;; Pin the inline renderer per session: the alt-screen one virtualises its own
  ;; scrollback, so the transcript never reaches the buffer (upstream #202).
  ;; Covers consumers whose own settings.json replaces the dotless one.
  (unless (string-match-p "--settings" claude-code-ide-cli-extra-flags)
    (setq claude-code-ide-cli-extra-flags
          (string-trim (concat claude-code-ide-cli-extra-flags
                               " --settings '{\"tui\":\"default\"}'"))))

  (defun my/claude-tutor-feedback ()
    "Ask Claude Code for Socratic feedback on the current file."
    (interactive)
    (claude-code-ide-send-prompt
     (format "I'm working on %s — Socratic feedback only. Point at problems and ask guiding questions. Do not write code or give away answers."
             (buffer-file-name))))

  (map! :leader :prefix "l" :desc "Tutor feedback" :nv "T" #'my/claude-tutor-feedback)

  (claude-code-ide-emacs-tools-setup))
