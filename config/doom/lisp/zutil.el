;;; zutil.el --- ZzAntares' Utilities -*- lexical-binding: t; -*-

;; TODO rename prefix 'zz/' -> 'zutil-'
;; TODO rather than having a file for centralizing helper functions
;;      create '-extra.el' libraries that also contain configuration
;;      for those options, or maybe just use Doom Modules for this sort of stuff

(require 'auth-source)                  ; Secret management


;;; Doom specific
(defvar doom-module-config-file)
(defvar doom-user-dir)

(defun zz/goto-doom-config-file ()
  "Open the doom config.el file."
  (interactive)
  (find-file (expand-file-name doom-module-config-file doom-user-dir)))

;;; Secret management

;; TODO There's a `zz/auth-info-key` in zstd that could be used to define this helper
(defun zz/llm-provider-api-key (provider)
  "Retrieve API key for LLM PROVIDER from the auth-source facilities.

Supported providers are `openai' `anthropic' `kagi' `google'.

`provider' is matched against the :login value.

Note, in most cases this function is not necessary if the consumer can
read the key from an environment variable, in that case the secret is
best stored and managed by SOPS at the HomeManager configuration level."
  (let ((host (pcase provider
                ('openai "api.openai.com")
                ('anthropic "api.anthropic.com")
                ('kagi "kagi.com")
                ('google "generativelanguage.googleapis.com")
                ('openrouter "openrouter.ai")
                (_ (error "Invalid llm provider. Use 'openai or 'anthropic")))))
    (auth-info-password
     (car (auth-source-search :host host
                              :login "apikey" ;; ensures compatibility between gptel and chatgpt-shell
                              :require '(:secret))))))


;;; Keybinding exploration helpers

(defun zz-key-binding-at-point (key)
  (mapcar (lambda (keymap) (when (keymapp keymap)
                             (lookup-key keymap key)))
          (list
           ;; More likely
           (get-text-property (point) 'keymap)
           (mapcar (lambda (overlay)
                     (overlay-get overlay 'keymap))
                   (overlays-at (point)))
           ;; Less likely
           (get-text-property (point) 'local-map)
           (mapcar (lambda (overlay)
                     (overlay-get overlay 'local-map))
                   (overlays-at (point))))))

(defun zz-locate-key-binding (key)
  "Determine in which keymap KEY is defined."
  (interactive "kPress key: ")
  (let ((ret
         (list
          (zz-key-binding-at-point key)
          (minor-mode-key-binding key)
          (local-key-binding key)
          (global-key-binding key))))
    (when (called-interactively-p 'any)
      (message "At Point: %s\nMinor-mode: %s\nLocal: %s\nGlobal: %s"
               (or (nth 0 ret) "")
               (or (mapconcat (lambda (x) (format "%s: %s" (car x) (cdr x)))
                              (nth 1 ret) "\n             ")
                   "")
               (or (nth 2 ret) "")
               (or (nth 3 ret) "")))
    ret))

(defun zz-keymaps-at-point ()
  "List entire keymaps present at point."
  (interactive)
  (let ((map-list
         (list
          (mapcar (lambda (overlay)
                    (overlay-get overlay 'keymap))
                  (overlays-at (point)))
          (mapcar (lambda (overlay)
                    (overlay-get overlay 'local-map))
                  (overlays-at (point)))
          (get-text-property (point) 'keymap)
          (get-text-property (point) 'local-map))))
    (apply #'message
           (concat
            "Overlay keymap: %s\n"
            "Overlay local-map: %s\n"
            "Text-property keymap: %s\n"
            "Text-property local-map: %s")
           map-list)))


;;; Misc

(defun zz/fill-comment-paragraph ()
  "Typically comments should be wrapped to a different `fill-column' value."
  (interactive)
  ;; TODO reliable detect comment paragraphs
  ;; TODO fill based on the start of the comment and end of the comment
  ;; TODO Expose a variable to customize the fill column
  (let ((fill-column 79))
    (fill-paragraph)))


(provide 'zutil)
