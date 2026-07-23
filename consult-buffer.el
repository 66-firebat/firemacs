;; -*- lexical-binding: t; -*-
;;
;; =============================================================================
;;  consult-buffer.el — Consult configuration & custom sources
;;
;;  General Consult configuration and all custom `consult-buffer' sources live
;;  here.  Loaded eagerly — no `with-eval-after-load'.
;; =============================================================================

;; ── Previous buffer source ─────────────────────────────────────

(defvar my/consult-source-previous
  `(:name     "Previous"
    :category buffer
    :face     consult-buffer
    :state    ,#'consult--buffer-state
    :items    ,(lambda ()
                 (when-let ((buf (other-buffer)))
                   (list (buffer-name buf)))))
  "Consult source showing the most recently selected buffer.
Appears as a single-candidate \"Previous\" section at the top.")

;; ── Ghostel source ────────────────────────────────────────────
;; Allows typing a number in consult-buffer to spawn a ghostel
;; terminal at that index.  Existing ghostel buffers appear as candidates.
;;
;; :default t ensures our :new is picked first by consult--multi-lookup.
;;
;; Our :new handles both cases:
;;   "90"         -> spawn ghostel terminal at index 90
;;   "README.md"  -> create a regular buffer (via consult--buffer-action)

(defvar my/consult-ghostel-source
  `(:name     "Ghostel"
    :category buffer
    :default  t
    :face     consult-buffer
    :history  buffer-name-history
    :state    ,#'consult--buffer-state
    :new      ,(lambda (name)
                 (if (string-match-p "\\`[0-9]+\\'" name)
                     (let ((buf (my/ghostel-spawn-at-index (string-to-number name))))
                       (when buf
                         (consult--buffer-action buf)))
                   (consult--buffer-action name)))
    :items    ,(lambda ()
                 (mapcar #'buffer-name (my/ghostel-buffer-list))))
  "Custom consult-buffer source for ghostel terminals.
Allows spawning a new ghostel by entering its index.
Uses `my/ghostel-spawn-at-index' and `my/ghostel-buffer-list' from ghostfire.el.")

(add-to-list 'consult-buffer-sources 'my/consult-ghostel-source)

;; ── Filter ghostel buffers from the default "Buffer" section ──

(defvar my/consult-source-buffer-no-ghostel
  `( :name     "Buffer"
     :narrow   ?b
     :category buffer
     :face     consult-buffer
     :history  buffer-name-history
     :state    ,#'consult--buffer-state
     :default  t
     :items
     ,(lambda ()
        (consult--buffer-query :sort 'visibility
                               :as #'consult--buffer-pair
                               :predicate (lambda (b)
                                            (not (with-current-buffer b
                                                   (derived-mode-p 'ghostel-mode)))))))
  "Like `consult-source-buffer' but excludes ghostel-mode buffers.

These are shown separately in the \"Ghostel\" section from
`my/consult-ghostel-source'.")

(setq consult-buffer-sources
      (mapcar (lambda (s)
                (if (eq s 'consult-source-buffer)
                    'my/consult-source-buffer-no-ghostel
                  s))
              consult-buffer-sources))

;; Prepend Previous so it appears at the VERY top
(add-to-list 'consult-buffer-sources 'my/consult-source-previous)


(provide 'consult-buffer)
;; consult-buffer.el ends here
