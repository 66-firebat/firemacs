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
;; =============================================================================

(use-package cooked
  ;; Installed via package-vc (not MELPA).  The :rev/:newest lets us track main.
  ;; NOTE: cooked needs its whole repo on disk (Cargo.toml, terminfo/,
  ;; shell-integration/) — package-vc keeps that.  The native core builds with
  ;; cargo on first M-x cooked (takes ~1 min, one-time).
  :vc (:url "https://github.com/vodik/cooked"
       :lisp-dir "lisp"
       :rev :newest)
  :commands (cooked cooked-other-window)
  :config
  ;; Opt-in extras for testing (see comments for what to try).
  (require 'cooked-evil)                 ; evil state auto-switching + [[ / ]]
  ;; Load completion EAGERLY so `cooked-shell-completion-functions' is non-nil
  ;; BEFORE any shell is spawned.  If it's nil at spawn time, cooked bakes a
  ;; startup file that does NOT source cooked-completion.bash, and TAB then
  ;; silently does nothing in that shell (the capture can't be retrofitted).
  (require 'cooked-shell-completion)     ; TAB -> shell-native completion
  (require 'cooked-command-decorations)  ; fringe marker per command (exit code)
  ;; (require 'cooked-next-error)        ; M-g M-n over one command's output
  ;; (require 'cooked-file-link)         ; clickable file:line links in output
  ;; (require 'cooked-project)           ; one terminal per project root
  ;; (require 'cooked-process)           ; pty for M-x compile / grep
  ;;                                     ;   (then: (cooked-process-mode 1))

  ;; Make sure the `completion' feature is ON (it is by default, but be explicit)
  ;; so the shell-integration snippet sources the completion capture.
  (setq cooked-shell-integration-features
        '(marks input-mark cwd announce completion title))

  ;; Unlimited scrollback (mirrors our ghostel setting: ghostel-scrollback-size nil).
  (setq cooked-scrollback-lines nil))

(provide 'cooked)
;; cooked.el ends here
