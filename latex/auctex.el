;;; auctex.el — AUCTeX configuration for LaTeX editing
;;;
;;; Loaded from init.el via (my/load-module "latex/auctex.el")

(message "[auctex] loading...")

;; ── Ensure AUCTeX is installed ──────────────────────────────────────

(unless (package-installed-p 'auctex)
  (package-refresh-contents)
  (package-install 'auctex))

;; ── Register .tex → LaTeX-mode (must happen at startup) ────────────

;; AUCTeX is installed in this config's own elpa/ directory, but
;; package-initialize may not have the path set up yet.  Two fallbacks:
;;   1. Try require directly (works if load-path already has it).
;;   2. Otherwise, find the directory and add it ourselves.
(condition-case err
    (progn
      (message "[auctex] trying require tex-site...")
      (require 'tex-site)
      ;; tex-site.el doesn't load auctex.el (which defines AUCTeX-version
      ;; and other package metadata).  Load the autoloads or auctex.el directly.
      (load "auctex" t t)
      (message "[auctex] tex-site loaded OK"))
  (file-missing
   (message "[auctex] tex-site not on load-path, searching...")
   (let* ((glob (expand-file-name "elpa/auctex-*" user-emacs-directory))
          (dirs (file-expand-wildcards glob)))
     (message "[auctex] glob=%s dirs=%s" glob dirs)
     (if dirs
         (progn
           (add-to-list 'load-path (car (last dirs)))
           (message "[auctex] added %s to load-path" (car (last dirs)))
           (require 'tex-site)
           (load "auctex" t t)
           (message "[auctex] tex-site loaded after path fix"))
       (message "[auctex] WARNING: no auctex dir found")))))

;; ── All settings (deferred until tex.el actually loads) ─────────────

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

  (setq TeX-view-program-list
        '(("Sioyek" "sioyek %o")))
  (setq TeX-view-program-selection
        '((output-pdf "Sioyek")))

  ;; ── RefTeX (built-in) — TOC, citations, cross-references ────────

  (add-hook 'LaTeX-mode-hook 'turn-on-reftex)
  (setq reftex-plug-into-AUCTeX t)

  ;; ── CDLaTeX (bundled) — fast math shorthand ─────────────────────

  (add-hook 'LaTeX-mode-hook 'turn-on-cdlatex)

  ;; ── Statuscolumn — sc-mode needs explicit re-enable ─────────────

  (add-hook 'LaTeX-mode-hook (lambda () (sc-mode 1))))

(provide 'auctex)
;;; auctex.el ends here
