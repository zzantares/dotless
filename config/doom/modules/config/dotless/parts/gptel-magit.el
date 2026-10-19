;;; parts/gptel-magit.el -*- lexical-binding: t; -*-

;; Use Claude Code CLI for gptel-magit features instead of gptel.
;; Overrides `gptel-magit--generate' and `gptel-magit--do-diff-request'.
(after! gptel-magit
  (defun +llm--claude-code-request (input system-prompt append-prompt callback error-prefix &optional model)
    "Send INPUT to Claude Code CLI and call CALLBACK with the result text.
SYSTEM-PROMPT and APPEND-PROMPT are passed as --system-prompt and
--append-system-prompt respectively.  ERROR-PREFIX labels minibuffer
error messages.  MODEL is an optional claude CLI model alias or full
model ID, defaulting to \"haiku\"."
    (let* ((input-file (make-temp-file "claude-input-"))
           (output ""))
      (with-temp-file input-file (insert input))
      (make-process
       :name "claude-request"
       :command (list "sh" "-c"
                      (format "claude -p --output-format json --model %s --system-prompt %s --append-system-prompt %s --no-session-persistence < %s"
                              (shell-quote-argument (or model "haiku"))
                              (shell-quote-argument system-prompt)
                              (shell-quote-argument append-prompt)
                              (shell-quote-argument input-file)))
       :noquery t
       :filter (lambda (_proc str)
                 (setq output (concat output str)))
       :sentinel (lambda (_proc event)
                   (delete-file input-file t)
                   (if (string-prefix-p "finished" event)
                       (let* ((json-line (car (split-string output "\n")))
                              (result (gethash "result" (json-parse-string json-line))))
                         (funcall callback (string-trim result)))
                     (message "%s error: %s%s"
                              error-prefix
                              (string-trim event)
                              (if (string-empty-p output) ""
                                (concat "\n" output))))))))

  (defadvice! +llm--claude-code-magit-generate-a (callback)
    :override #'gptel-magit--generate
    (message "claude: Generating commit message...")
    (+llm--claude-code-request
     (magit-git-output "diff" "--cached")
     (gptel-magit--get-commit-prompt)
     "Output ONLY the raw commit message. No preamble, no markdown code fences, no Co-Authored-By trailer, no explanation."
     callback
     "claude-commit"))

  (defadvice! +llm--claude-code-magit-diff-explain-a (diff)
    :override #'gptel-magit--do-diff-request
    (message "claude: Explaining diff...")
    (+llm--claude-code-request
     diff
     gptel-magit-diff-explain-prompt
     "Output ONLY the explanation in Markdown. No preamble like \"Here is the explanation\"."
     #'gptel-magit--show-diff-explain
     "claude-diff-explain")))
