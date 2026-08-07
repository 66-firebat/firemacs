;;; auctex.el — AUCTeX configuration for LaTeX editing
;;;
;;; Loaded from init.el via (my/load-module "latex/auctex.el")

;; ── Ensure AUCTeX is installed ──────────────────────────────────────

(unless (package-installed-p 'auctex)
  (package-refresh-contents)
  (package-install 'auctex))

;; ── Register .tex → LaTeX-mode ─────────────────────────────────────

(condition-case _
    (progn
      (require 'tex-site)
      (load "auctex" t t))
  (file-missing
   (let* ((glob (expand-file-name "elpa/auctex-*" user-emacs-directory))
          (dirs (file-expand-wildcards glob)))
     (when dirs
       (add-to-list 'load-path (car (last dirs)))
       (require 'tex-site)
       (load "auctex" t t)))))

;; ── Settings (deferred until AUCTeX loads on first .tex file) ───────

(with-eval-after-load 'tex

  ;; ── Core behavior ────────────────────────────────────────────────

  (setq TeX-parse-self t)
  (setq TeX-auto-save t)
  (setq-default TeX-master nil)
  (setq TeX-PDF-mode t)
  (setq TeX-command-default "LatexMk")
  (setq TeX-show-compilation t)

  ;; ── SyncTeX + Sioyek ────────────────────────────────────────────

  (setq TeX-source-correlate-mode t)

  ;; Base viewer: open Sioyek with the PDF.
  ;; When source-correlate is active (built after compiling with
  ;; --synctex=1), forward-search args are appended automatically
  ;; by the mode-io-correlate predicate below.
  (setq TeX-view-program-list
        '(("Sioyek"
           ("sioyek %o"
            (mode-io-correlate
             " --forward-search-file %s --forward-search-line %n --inverse-search \"emacsclient --no-wait +%2 %1\"")))))
  (setq TeX-view-program-selection
        '((output-pdf "Sioyek")))

  ;; ── RefTeX (built-in) — TOC, citations, cross-references ────────

  (add-hook 'LaTeX-mode-hook 'turn-on-reftex)
  (setq reftex-plug-into-AUCTeX t)

  ;; ── CDLaTeX (bundled) — fast math shorthand ─────────────────────

  (add-hook 'LaTeX-mode-hook 'turn-on-cdlatex)

  ;; ── Statuscolumn ────────────────────────────────────────────────

  (add-hook 'LaTeX-mode-hook (lambda () (sc-mode 1))))

(provide 'auctex)
;;; auctex.el ends here
