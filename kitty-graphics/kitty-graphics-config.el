;; -*- lexical-binding: t; -*-
;;
;; =============================================================================
;;  kitty-graphics-config.el — Terminal graphics (images, LaTeX, PDF)
;;
;;  Integrates kitty-graphics.el into Firemacs.  The package renders images,
;;  LaTeX/typst previews, PDF documents, and more directly in terminal Emacs
;;  using the Kitty graphics protocol (supported by Ghostty) or Sixel.
;;
;;  Features:
;;    - org-mode inline images (C-c C-x C-v)
;;    - LaTeX fragment previews (C-c C-x C-l)
;;    - PDF/DVI/PS/EPUB via doc-view
;;    - shr image scaling (eww, elfeed)
;;    - Dired image previews
;;
;;  Requirements:
;;    - Ghostty (or Kitty, foot, WezTerm — any Kitty/Sixel-capable terminal)
;;    - dvipng or dvisvgm for LaTeX previews
;;    - mutool or Ghostscript for PDF/doc-view
;;    - ImageMagick (convert) for non-PNG image conversion
;;
;;  Source: https://github.com/cashmeredev/kitty-graphics.el
;;  Bundled kitty-graphics.el v1.3.0
;; =============================================================================

;; ── Load the bundled library ────────────────────────────────────

;; kitty-graphics.el is a single-file library with no MELPA package.
;; We bundle it directly like neoscroll.el.
(let ((real-dir (file-name-directory
                 (file-truename (or load-file-name buffer-file-name)))))
  (load (expand-file-name "kitty-graphics.el" real-dir)))

;; ── Configuration ───────────────────────────────────────────────

;; Sane max dimensions for inline images (terminal-friendly)
(setq kitty-graphics-max-width 100)
(setq kitty-graphics-max-height 40)

;; Scale shr (eww/elfeed) images to fit the window width
(setq kitty-graphics-shr-scale 'fit)
(setq kitty-graphics-shr-fit-width 0.6)

;; Scale org-mode inline images to fit
(setq kitty-graphics-org-image-scale 'fit)
(setq kitty-graphics-org-image-fit-width 0.8)

;; ── Activate ────────────────────────────────────────────────────

;; kitty-graphics-setup handles both plain terminal Emacs and daemon
;; with multiple emacsclient -t instances.  It auto-detects the
;; backend (Kitty protocol on Ghostty, Sixel as fallback).
(kitty-graphics-setup)

;; At startup the terminal may not be fully initialised (KKP, shell
;; integration, etc. are still setting up).  If kitty-graphics-mode
;; self-disabled because detection failed, retry after init is done.
(add-hook 'emacs-startup-hook
          (lambda ()
            (unless kitty-graphics-mode
              (kitty-graphics-mode 1))))

;; ── Diagnostic helper ───────────────────────────────────────────

(defun my/kitty-latex-check ()
  "Quick diagnostic: verify kitty-graphics + org-latex-preview are wired."
  (interactive)
  (require 'org)
  (with-current-buffer (get-buffer-create "*kitty-latex-check*")
    (erase-buffer)
    (insert (format "kitty-graphics-mode: %s\n" kitty-graphics-mode))
    (insert (format "display-graphic-p:   %s\n" (display-graphic-p)))
    (insert (format "KITTY_PID env:        %s\n" (getenv "KITTY_PID")))
    (insert (format "TERM:                 %s\n" (getenv "TERM")))
    (insert (format "org-latex-preview advised: %s\n"
                    (advice-member-p #'kitty-graphics--org-latex-preview-advice
                                     'org-latex-preview)))
    (insert (format "org--make-preview-overlay advised: %s\n"
                    (advice-member-p #'kitty-graphics--org-make-preview-overlay-advice
                                     'org--make-preview-overlay)))
    (display-buffer (current-buffer))))

(provide 'kitty-graphics-config)
;; kitty-graphics-config.el ends here
