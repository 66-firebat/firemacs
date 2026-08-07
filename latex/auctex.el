;;; auctex.el — Minimal AUCTeX configuration for LaTeX editing
;;;
;;; Loaded from init.el via (my/load-module "latex/auctex.el")
;;;
;;; AUCTeX provides the `latex' feature.  `cdlatex' (math shorthand) and
;;; `reftex' (cross-references) are both bundled — no extra packages needed.

(use-package auctex
  :ensure t
  :init
  ;; tex-site.el must load eagerly so AUCTeX registers itself to handle
  ;; .tex files (via auto-mode-alist).  Without this, the built-in
  ;; latex-mode from tex-mode.el wins and AUCTeX never activates.
  ;; tex-site.el is tiny — it only sets up paths and mode detection.
  (require 'tex-site)
  :config

  ;; ── Core behavior ──────────────────────────────────────────────────

  (setq TeX-parse-self t)              ; Parse preamble for macros/envs
  (setq TeX-auto-save t)               ; Cache parse results to disk
  (setq-default TeX-master nil)        ; Ask master/sub-file on first open
  (setq TeX-PDF-mode t)                ; Produce PDF, not DVI
  (setq TeX-command-default "LatexMk") ; latexmk handles the build loop
  (setq TeX-show-compilation t)        ; Show output in split window

  ;; ── SyncTeX + Sioyek ───────────────────────────────────────────────

  ;; Embed SyncTeX data during compilation so forward/inverse search works.
  (setq TeX-source-correlate-mode t)

  ;; Configure Sioyek as the PDF viewer.
  (setq TeX-view-program-list
        '(("Sioyek" "sioyek --reuse-instance %o")))
  (setq TeX-view-program-selection
        '((output-pdf "Sioyek")))

  ;; ── RefTeX (built-in) — TOC, citations, cross-references ──────────

  (add-hook 'LaTeX-mode-hook 'turn-on-reftex)
  (setq reftex-plug-into-AUCTeX t)

  ;; ── CDLaTeX (bundled) — fast math shorthand ───────────────────────

  (add-hook 'LaTeX-mode-hook 'turn-on-cdlatex)

  ;; ── Statuscolumn — sc-mode needs explicit re-enable in LaTeX buffers ──

  (add-hook 'LaTeX-mode-hook (lambda () (sc-mode 1))))

(provide 'auctex)
;;; auctex.el ends here
