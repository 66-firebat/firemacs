;;; auctex.el — Minimal AUCTeX configuration for LaTeX editing
;;;
;;; Loaded from init.el via (my/load-module "latex/auctex.el")
;;;
;;; Architecture:
;;;   - (:init)  tex-site.el registers .tex → LaTeX-mode on auto-mode-alist
;;;   - (:defer) AUCTeX (tex.el/latex.el) only loads when first .tex opens
;;;   - (:config) our settings fire when tex.el loads, before LaTeX-mode runs

(use-package tex
  :ensure auctex
  :defer t
  :init
  ;; tex-site.el must load eagerly so AUCTeX claims .tex files from the
  ;; built-in latex-mode.  It does NOT load the full tex.el — that's
  ;; deferred until the first .tex file is opened.
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

  (setq TeX-source-correlate-mode t)

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
