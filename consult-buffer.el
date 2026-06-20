;; -*- lexical-binding: t; -*-
;;
;; =============================================================================
;;  consult-buffer.el — Consult configuration & custom sources
;;
;;  General Consult configuration and all custom `consult-buffer' sources live
;;  here.  Loaded eagerly — no `with-eval-after-load'.
;; =============================================================================

;; ── VTerm source ───────────────────────────────────────────────
;; Allows typing a number in SPC b b (consult-buffer) to spawn a
;; vterm at that index.  Existing vterm buffers appear as candidates.

(defvar my/consult-vterm-source
  `(:name     "VTerm"
    :category buffer
    :face     consult-buffer
    :history  buffer-name-history
    :state    ,#'consult--buffer-state
    :new      ,(lambda (name)
                 (my/vterm-spawn-at-index (string-to-number name)))
    :items    ,(lambda ()
                 (mapcar #'buffer-name (my/vterm-buffer-list))))
  "Custom consult-buffer source for vterm buffers.
Allows spawning a new vterm by entering its index.
Uses `my/vterm-spawn-at-index' and `my/vterm-buffer-list' from keybinds.el.")

(add-to-list 'consult-buffer-sources 'my/consult-vterm-source t)

;; ── Future consult sources go here ──────────────────────────────

(provide 'consult-buffer)
;; consult-buffer.el ends here
