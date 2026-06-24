;; -*- lexical-binding: t; -*-
;;
;; =============================================================================
;;  scroll-on-jump.el — Animated cursor movement for j/k and all jump commands
;;
;;  Animates ANY cursor motion (j, k, gg, G, /, n, N, etc.) by breaking
;;  the jump into smaller steps with easing.
;;
;;  Install: M-x package-install RET scroll-on-jump RET
;; =============================================================================

(use-package scroll-on-jump
  :ensure t
  :demand t
  :config
  ;; Animation duration in seconds
  (setq scroll-on-jump-duration 0.15)

  ;; Smooth pixel scrolling when available
  (setq scroll-on-jump-smooth t)

  ;; Easing curve
  (setq scroll-on-jump-curve 'smooth)

  ;; Prevent Emacs from recentering during animated jumps
  ;; (default 0 recenters aggressively; 101 = scroll minimum only)
  (setq scroll-conservatively 101)
  (setq scroll-margin 0)

  ;; Global mode — covers most point-moving commands
  (scroll-on-jump-global-mode 1)

  ;; Evil-specific advice — only for BIG jumps, not j/k
  (with-eval-after-load 'evil
    (scroll-on-jump-advice-add evil-goto-line)
    (scroll-on-jump-advice-add evil-goto-first-line)
    (scroll-on-jump-advice-add evil-forward-paragraph)
    (scroll-on-jump-advice-add evil-backward-paragraph)
    (scroll-on-jump-advice-add evil-ex-search-next)
    (scroll-on-jump-advice-add evil-ex-search-previous)))

(provide 'scroll-on-jump)
;; scroll-on-jump.el ends here
