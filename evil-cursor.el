;; -*- lexical-binding: t; -*-
;;
;; =============================================================================
;;  evil-cursor.el — Per-state terminal cursor colors
;;
;;  When running Emacs in a terminal (emacs -nw), changes the cursor color
;;  based on the current evil state using OSC 12 / OSC 112 escape sequences.
;;
;;  Normal mode  → Terminal default (reset)
;;  Insert mode  → #00ff00 (green)
;;  Visual mode  → #0000ff (blue)
;;
;;  Works by advising `evil-set-cursor', which evil calls on every state
;;  transition.  The :after advice sends the escape sequence to the outer
;;  terminal — it runs after evil has already set the cursor shape, so
;;  shape and color are both managed correctly.
;;
;;  Works in all buffers, including eat terminals, because
;;  `send-string-to-terminal' bypasses Emacs' internal buffer system and
;;  writes directly to the outer terminal's file descriptor.
;; =============================================================================

;; ── Color map ───────────────────────────────────────────────────

(defvar my/evil-cursor-colors
  '((normal . nil)           ;; nil = reset to terminal default
    (insert . "#00ff00")     ;; green
    (visual . "#0000ff"))    ;; blue
  "Cursor colors per evil state.
Each entry is (STATE . COLOR).  COLOR is an X11 color string
suitable for OSC 12, or nil to reset to terminal default.")

;; ── Terminal escape helpers ─────────────────────────────────────

(defun my/send-cursor-color (color)
  "Send OSC 12 escape sequence to set terminal cursor color to COLOR.
COLOR is a string like \"#00ff00\" or nil to reset to default."
  (if color
      (send-string-to-terminal (format "\033]12;%s\007" color))
    (send-string-to-terminal "\033]112\007")))

;; ── Evil integration ────────────────────────────────────────────

(defun my/evil-set-cursor-color (&rest _args)
  "After `evil-set-cursor', send terminal escape for current evil state.
Uses `alist-get' to look up the color for `evil-state'."
  (when (not (display-graphic-p))
    (my/send-cursor-color (alist-get evil-state my/evil-cursor-colors))))

;; Hook into evil's cursor setup — runs on every state transition,
;; after evil has already set the cursor shape.
(advice-add 'evil-set-cursor :after #'my/evil-set-cursor-color)


(provide 'evil-cursor)
;; evil-cursor.el ends here
