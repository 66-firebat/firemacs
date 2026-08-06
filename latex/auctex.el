;;; auctex.el — Minimal AUCTeX configuration for LaTeX editing
;;;
;;; Loaded from init.el via (my/load-module "latex/auctex.el")
;;; Settings that depend on AUCTeX are wrapped in with-eval-after-load
;;; so they don't trigger before AUCTeX is actually used.

;; ---------------------------------------------------------------------------
;;  1.  Core AUCTeX Behavior (deferred until AUCTeX loads)
;; ---------------------------------------------------------------------------

(with-eval-after-load 'latex
  ;; Parse the current file for macro/environment/package information.
  (setq TeX-parse-self t)

  ;; Cache the parsed data so it persists across sessions.
  (setq TeX-auto-save t)

  ;; Ask whether a .tex file is master or sub-file on first open.
  (setq-default TeX-master nil)

  ;; Produce PDF output instead of DVI.
  (setq TeX-PDF-mode t)

  ;; Default command: latexmk handles the pdflatex → bibtex → pdflatex × 2 loop.
  (setq TeX-command-default "LatexMk")

  ;; Show compilation output in a split window.
  (setq TeX-show-compilation t)

  ;; ---------------------------------------------------------------------------
  ;;  2.  RefTeX — Cross-references, citations, table of contents
  ;; ---------------------------------------------------------------------------

  ;; RefTeX ships with Emacs.  It provides:
  ;;   C-c =     → table of contents
  ;;   C-c [     → insert \cite{} with completion over .bib files
  ;;   C-c )     → insert \ref{} with completion over \label{}s
  ;;   C-c (     → insert \label{} automatically
  (add-hook 'LaTeX-mode-hook 'turn-on-reftex)
  (setq reftex-plug-into-AUCTeX t)

  ;; ---------------------------------------------------------------------------
  ;;  3.  CDLaTeX — Fast math insertion (only in LaTeX buffers)
  ;; ---------------------------------------------------------------------------

  ;; cdlatex is bundled with AUCTeX.  Shorthand expansions:
  ;;   `a    → \alpha     `d    → \delta
  ;;   _     → _{}         ^     → ^{}
  ;;   SPACE after macro name → auto-inserts braces
  (add-hook 'LaTeX-mode-hook 'turn-on-cdlatex))

(provide 'auctex)
;;; auctex.el ends here
