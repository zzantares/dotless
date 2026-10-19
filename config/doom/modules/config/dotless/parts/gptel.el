;;; parts/gptel.el -*- lexical-binding: t; -*-

(after! gptel
  (setopt gptel-model 'fastgpt
          gptel-backend (gptel-make-kagi "Kagi" :key #'gptel-api-key-from-auth-source)))
