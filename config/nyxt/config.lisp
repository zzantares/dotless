(define-configuration-buffer
    ((override-map
      (let ((the-map (make-keymap "override-map")))
        (define-key the-map
          "k" 'scroll-down
          "h" 'scroll-up
          "j" 'scroll-left
          "l" 'scroll-right
          "C-u" 'scroll-page-up
          "C-d" 'scroll-page-down
          "C-f" 'scroll-right
          "C-b" 'scroll-left
          "G" 'scroll-to-bottom
          "g g" 'scroll-to-top
          "b" 'switch-buffer
          "L" 'switch-buffer-next
          "J" 'switch-buffer-previous
          "H" 'history-forwards
          "K" 'history-backwards
          "Y" 'copy-url
          "y" 'copy
          "p" 'paste
          "/" 'search-buffer
          "SPC /" 'search-buffers
          "SPC q q" 'quit
          "M-x" 'execute-command)))))
