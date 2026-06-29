;; -*- lexical-binding: t; -*-

(use-package julia-ts-mode
  :ensure nil     ;; Built into Emacs 29+, not on MELPA
  :mode "\\.jl\\'")

(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
    '(((julia-mode :language-id "julia")
       (julia-ts-mode :language-id "julia"))
      "jetls" "serve" "--socket" :autoport)))

(provide 'julia)
;; julia.el ends here
