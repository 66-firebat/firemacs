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
  "t t" '(vterm :which-key "open vterm")

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

(provide 'keybinds)
;; keybinds.el ends here
