;;; auctex.el — Minimal AUCTeX configuration for LaTeX editing
;;;
;;; Loaded from init.el via (my/load-module "latex/auctex.el")

;; ── Ensure AUCTeX is installed ──────────────────────────────────────

(unless (package-installed-p 'auctex)
  (package-refresh-contents)
  (package-install 'auctex))

;; ── Find and load tex-site.el (registers .tex → LaTeX-mode) ────────

;; package-initialize doesn't always add the package dir to load-path,
;; so we find it explicitly.  The glob handles version upgrades.
(let ((auctex-dirs (file-expand-wildcards
                    (expand-file-name "elpa/auctex-*" user-emacs-directory))))
  (when auctex-dirs
    (add-to-list 'load-path (car (last auctex-dirs)))))

(require 'tex-site)

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
        '(("Sioyek" "sioyek --reuse-instance %o")))
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
