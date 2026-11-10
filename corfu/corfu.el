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
;;
;;  Key handling: corfu binds TAB -> `corfu-complete' (and M-TAB -> `corfu-expand')
;;  in its own `corfu-mode-map', which is a buffer-local minor-mode map and
;;  therefore takes precedence over evil's insert-state TAB binding.  No manual
;;  rebinding is needed here.  The `evil-want-C-i-jump' setting (init.el) and the
;;  `[C-i]' -> `evil-jump-forward' bindings (keybinds.el) only affect
;;  normal/visual state, so jump-forward and cooked completion don't conflict.
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

  ;; Force-enable corfu in cooked terminal buffers.  `global-corfu-mode'
  ;; deliberately skips buffers whose name starts with a space or that are
  ;; read-only; cooked's editable input line is neither, but ensuring here makes
  ;; TAB completion reliable regardless of the global-mode predicate.
  (with-eval-after-load 'cooked-mode
    (add-hook 'cooked-mode-hook #'corfu-mode))

  ;; TAB is not bound in `corfu-mode-map' (only the popup's `corfu-map' has it).
  ;; At a cooked prompt we need TAB to trigger `completion-at-point', which
  ;; cooked-evil already binds in insert state.  Here we add a safe fallback that
  ;; binds TAB directly on `cooked-mode-map' (a plain `define-key', no evil
  ;; auxiliary-map machinery, so no `keymapp' race).
  (with-eval-after-load 'cooked-mode
    (define-key cooked-mode-map (kbd "TAB") #'corfu-complete)))

(provide 'corfu)
;; corfu.el ends here
