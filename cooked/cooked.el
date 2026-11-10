;; -*- lexical-binding: t; -*-
;;
;; =============================================================================
;;  cooked.el — minimal cooked terminal emulator install for testing
;;
;;  This is a STAGING install only.  It does not replace ghostel: ghostel is
;;  still loaded in init.el and still owns all the existing keybindings
;;  (M-t, M-z, C-c C-m, etc.).  This file just makes `M-x cooked` available so
;;  you can try cooked out before the full port in PLAN.md.
;;
;;  Usage: M-x cooked            (spawn/focus a terminal)
;;         M-x cooked-other-window
;;
;;  Everything cooked-related is loaded EAGERLY (no :commands lazy-loading),
;;  which avoids the `keymapp cooked-mode-map` load-order race between
;;  cooked-mode, cooked-evil, and evil's auxiliary-keymap machinery.
;; =============================================================================

;; Install via package-vc (MELPA).  :demand t forces cooked to load NOW rather
;; than on first M-x cooked, so its files are fully available below.
(use-package cooked
  :vc (:url "https://github.com/vodik/cooked"
       :lisp-dir "lisp"
       :rev :newest)
  :demand t)

;; ── Eagerly load every cooked layer, in dependency order ────────────────────
(require 'cooked)                        ; main entry (M-x cooked)
(require 'cooked-mode)                   ; defines cooked-mode + cooked-mode-map
(require 'cooked-evil)                   ; evil state auto-switching + [[ / ]]
;; Load completion EAGERLY so `cooked-shell-completion-functions' is non-nil
;; BEFORE any shell is spawned.  If it's nil at spawn time, cooked bakes a
;; startup file that does NOT source cooked-completion.bash, and TAB then
;; silently does nothing in that shell (the capture can't be retrofitted).
(require 'cooked-shell-completion)       ; TAB -> shell-native completion
(require 'cooked-command-decorations)    ; fringe marker per command (exit code)

;; ── Configuration ───────────────────────────────────────────────────────────
;; Make sure the `completion' feature is ON (it is by default, but be explicit)
;; so the shell-integration snippet sources the completion capture.
(setq cooked-shell-integration-features
      '(marks input-mark cwd announce completion title))

;; Unlimited scrollback (mirrors our ghostel setting: ghostel-scrollback-size nil).
(setq cooked-scrollback-lines nil)

(provide 'cooked)
;; cooked.el ends here
