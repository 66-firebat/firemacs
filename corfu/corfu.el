;; -*- lexical-binding: t; -*-
;;
;; =============================================================================
;;  corfu.el — In-buffer completion UI (Corfu)
;;
;;  Corfu provides a small popup of `completion-at-point' candidates at point.
;;  This is the in-buffer completion frontend that vertico (minibuffer-only)
;;  does NOT provide.  It is what makes TAB pop up candidates inside a cooked
;;  terminal's editable input line (and anywhere else completion-at-point runs).
;;
;;  Without corfu/company, completion-at-point still runs but has no visible
;;  popup for ambiguous completions, so TAB appears to "do nothing".
;; =============================================================================

(use-package corfu
  :ensure t
  :demand t
  :custom
  (corfu-auto nil)                       ; no auto-popup; TAB triggers on demand
  (corfu-cycle t)                        ; wrap around the candidate list
  (corfu-preselect 'prompt)              ; preselect the first ("prompt") candidate
  (corfu-count 10)                       ; how many candidates to show
  :config
  (global-corfu-mode 1)                  ; enable corfu-mode in every buffer

  ;; Force-enable corfu in cooked terminal buffers, regardless of the
  ;; global-mode predicate.  NOTE: passing `#'corfu-mode' as the hook function
  ;; would TOGGLE it (minor modes toggle on a nil argument); we must pass
  ;; `(lambda () (corfu-mode 1))' to always enable.
  (with-eval-after-load 'cooked-mode
    (add-hook 'cooked-mode-hook (lambda () (corfu-mode 1))))

  ;; Bind every spelling of the Tab key to completion in cooked buffers.
  ;; In TUI Emacs with kkp (kitty keyboard protocol), the physical Tab key
  ;; arrives as `<tab>', not `TAB'/`C-i'.  cooked-evil binds TAB and C-i in
  ;; insert state but not `<tab>', so we add all three spellings directly on
  ;; `cooked-mode-map' (plain `define-key', no evil auxiliary-map race).
  (with-eval-after-load 'cooked-mode
    (define-key cooked-mode-map (kbd "<tab>") #'completion-at-point)
    (define-key cooked-mode-map (kbd "TAB") #'completion-at-point)
    (define-key cooked-mode-map (kbd "C-i") #'completion-at-point)))

(provide 'corfu)
;; corfu.el ends here
