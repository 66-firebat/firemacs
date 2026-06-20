;; -*- lexical-binding: t; -*-
;;
;; =============================================================================
;;  keybinds.el — All custom keybindings
;;
;;  Every keybinding in the Emacs configuration lives here.
;;  The `leader` key is defined in init.el (general-create-definer).
;; =============================================================================

;; ── Window navigation (normal mode) ────────────────────────────
;; Ctrl + hjkl to move between windows, like Vim
(general-def 'normal
  "C-h" 'evil-window-left
  "C-j" 'evil-window-down
  "C-k" 'evil-window-up
  "C-l" 'evil-window-right)

;; ── Avy — jump to any visible character ────────────────────────
;; s + one char  → jump to word starting with that char
;; S + two chars → jump to that exact character pair
;; g s           → jump to a visible line number
(general-def 'normal
  "s" 'avy-goto-word-1
  "S" 'avy-goto-char-2
  "gs" 'avy-goto-line)

;; ── Custom vterm buffer ───────────────────────────────
;; Always spawns a new vterm with incrementing index + PID.

(defvar my-vterm-counter -1
  "Incremented each time a new vterm is spawned via SPC t t.
Starts at -1 so the first spawn is index 0.")

(defun my/vterm-new ()
  "Spawn a new vterm buffer with an incrementing index and PID."
  (interactive)
  (setq my-vterm-counter (1+ my-vterm-counter))
  (let* ((index my-vterm-counter)
         (buf-name (format "vterm-%d -- waiting" index)))
    (vterm buf-name)
    (with-current-buffer buf-name
      (when (and (buffer-live-p (current-buffer))
                 vterm--process
                 (process-live-p vterm--process))
        (rename-buffer (format "vterm-%d -- %d" index
                                (process-id vterm--process)))))))

;; ── Previous buffer toggle ─────────────────────────────
;; Uses Emacs built-in other-buffer to go back to the last buffer.

(defun my/switch-to-other-buffer ()
  "Switch to the most recently viewed buffer.  Toggles A -> B -> A.
Uses `other-buffer' with the current buffer excluded so it returns
the actual second-most-recent buffer, not just an 'interesting' one."
  (interactive)
  (let ((other (other-buffer (current-buffer) t)))
    (if other
        (switch-to-buffer other)
      (message "No previous buffer available"))))

;; ── Excluded buffers for SPC b # ────────────────────────
;; Buffers matching these names or modes are skipped when
;; numbering buffers for `my/buffer-by-index'.

(defvar my/excluded-buffer-names '("*scratch*" "*Messages*")
  "Buffer names excluded from SPC b # navigation.")

(defvar my/excluded-buffer-modes '(vterm-mode)
  "Major modes excluded from SPC b # navigation.")

(defun my/filtered-buffer-list ()
  "Return buffer list excluding `my/excluded-buffer-names' and
`my/excluded-buffer-modes'."
  (delq nil
        (mapcar (lambda (b)
                  (with-current-buffer b
                    (unless (or (member (buffer-name) my/excluded-buffer-names)
                                (apply #'derived-mode-p my/excluded-buffer-modes))
                      b)))
                (buffer-list))))

;; ── SPC b # — jump to buffer by index ──────────────────

(defun my/buffer-by-index (index)
  "Switch to the non-excluded buffer at INDEX (0 = most recent).
Shows a numbered list before prompting."
  (interactive)
  (let ((bufs (my/filtered-buffer-list)))
    ;; Show numbered list in a help window
    (with-help-window "*Buffer Index*"
      (with-current-buffer standard-output
        (let ((n 0))
          (dolist (b bufs)
            (insert (format "%3d: %s\n" n (buffer-name b)))
            (setq n (1+ n))))))
    (unless bufs
      (user-error "No available buffers"))
    (if (and (natnump index) (< index (length bufs)))
        (switch-to-buffer (nth index bufs))
      (message "No buffer at index %d (max %d)" index (1- (length bufs))))))

(defun my/buffer-by-index-prompt ()
  "Prompt for a buffer index and switch to it."
  (interactive)
  (let ((bufs (my/filtered-buffer-list)))
    (my/buffer-by-index
     (read-number (format "Enter buffer number (0-%d): " (1- (length bufs)))))))

;; ── SPC v # — jump to vterm by index ───────────────────
;; Independent of the vterm counter system.  Switches to an
;; existing vterm or spawns one at the requested index.

(defun my/vterm-buffer-by-index (index)
  "Return the vterm buffer for INDEX, or nil if none exists."
  (car (seq-filter
        (lambda (b)
          (with-current-buffer b
            (and (derived-mode-p 'vterm-mode)
                 (string-match-p (format "\\`vterm-%d" index) (buffer-name b)))))
        (buffer-list))))

(defun my/vterm-spawn-at-index (index)
  "Create a new vterm buffer with the given INDEX."
  (let* ((buf-name (format "vterm-%d -- waiting" index)))
    (vterm buf-name)
    (with-current-buffer buf-name
      (when (and vterm--process (process-live-p vterm--process))
        (rename-buffer (format "vterm-%d -- %d" index
                                (process-id vterm--process)))))))

(defun my/vterm-by-index (index)
  "Switch to vterm INDEX, or spawn it if missing."
  (interactive)
  (let ((buf (my/vterm-buffer-by-index index)))
    (if buf
        (switch-to-buffer buf)
      (my/vterm-spawn-at-index index)
      (message "Spawned vterm-%d" index))))

(defun my/vterm-by-index-prompt ()
  "Prompt for a vterm index and switch to or spawn it."
  (interactive)
  (my/vterm-by-index (read-number "Enter vterm number: ")))

;; ── SPC leader keybindings ─────────────────────────────────────

(leader
  ;; Files
  "SPC" '(consult-buffer :which-key "switch buffer")
  "f f" '(find-file :which-key "find file")
  "f r" '(consult-recent-file :which-key "recent files")
  "f s" '(save-buffer :which-key "save buffer")

  ;; Buffers
  "b b" '(consult-buffer :which-key "switch buffer")
  "b d" '(kill-current-buffer :which-key "kill buffer")
  "b n" '(next-buffer :which-key "next buffer")
  "b p" '(previous-buffer :which-key "previous buffer")

  ;; Windows
  "w v" '(evil-window-vsplit :which-key "vertical split")
  "w s" '(evil-window-split :which-key "horizontal split")
  "w d" '(evil-window-delete :which-key "delete window")
  "w m" '(delete-other-windows :which-key "maximize window")
  "w h" '(evil-window-left :which-key "left window")
  "w j" '(evil-window-down :which-key "down window")
  "w k" '(evil-window-up :which-key "up window")
  "w l" '(evil-window-right :which-key "right window")

  ;; Project
  "p p" '(project-switch-project :which-key "switch project")
  "p f" '(project-find-file :which-key "project file")
  "p g" '(consult-grep :which-key "grep project")
  "p b" '(project-switch-to-buffer :which-key "project buffer")

  ;; Search
  "s s" '(consult-line :which-key "search line")
  "s g" '(consult-grep :which-key "grep")
  "s r" '(consult-ripgrep :which-key "ripgrep")

  ;; Git / Magit
  "g g" '(magit-status :which-key "magit status")
  "g d" '(magit-diff-unstaged :which-key "diff unstaged")
  "g l" '(magit-log :which-key "log")
  "g c" '(magit-commit :which-key "commit")
  "g p" '(magit-push :which-key "push")
  "g f" '(magit-fetch :which-key "fetch")
  "g b" '(magit-blame :which-key "blame")
  "g [" '(diff-hl-previous-hunk :which-key "previous hunk")
  "g ]" '(diff-hl-next-hunk :which-key "next hunk")

  ;; Toggle
  "t l" '(display-line-numbers-mode :which-key "toggle line numbers")
  "t w" '(whitespace-mode :which-key "toggle whitespace")
  "t t" '(my/vterm-new :which-key "new vterm")

  ;; Help
  "h f" '(describe-function :which-key "describe function")
  "h v" '(describe-variable :which-key "describe variable")
  "h k" '(describe-key :which-key "describe key")
  "h m" '(describe-mode :which-key "describe mode")

  ;; Eglot / LSP
  "l a" '(eglot-code-actions :which-key "code actions")
  "l r" '(eglot-rename :which-key "rename")
  "l f" '(eglot-format :which-key "format")

  ;; Org / Notes
  "n c" '(org-capture :which-key "capture")
  "n a" '(org-agenda :which-key "agenda"))

;; ── SPC b # and SPC v # (separate leader calls) ─────────
;; These are defined separately for clarity and to avoid deeply
;; nested (leader ...) forms.  SPC v uses a prefix-key structure
;; so additional vterm bindings can be added under it later.
(leader
  "b r" '(my/switch-to-other-buffer :which-key "previous buffer")
  "b #" '(my/buffer-by-index-prompt :which-key "buffer by number")
  ;; SPC v prefix — extend with more vterm bindings as needed
  "v #" '(my/vterm-by-index-prompt :which-key "vterm by number"))

(provide 'keybinds)
;; keybinds.el ends here
