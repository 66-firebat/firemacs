;; -*- lexical-binding: t; -*-
;;
;; =============================================================================
;;  vterm.el — Terminal Emulator Configuration
;;
;;  Built on the emacs-libvterm package (installed via NixOS).
;;  Requires: (emacsPackages.vterm) in configuration.nix
;;
;;  Design choices:
;;    - Vim-by-default: vterm starts in evil NORMAL state
;;    - `i` enters insert state; ESC returns to normal state
;;    - Shell integration enabled for directory tracking
;; =============================================================================

;; ── Load autoloads ─────────────────────────────────────────────
;; vterm is installed via NixOS, not MELPA, so package-initialize
;; doesn't register its autoloads. Load them explicitly so
;; M-x vterm (and SPC t t) appear as available commands.
(require 'vterm-autoloads)

;; ── Initial state: vim-by-default ──────────────────────────────
;; Start vterm in evil normal state so vim keys (j/k, gg, /, etc.)
;; work for buffer navigation. Only `i` passes through to the shell.
(evil-set-initial-state 'vterm-mode 'normal)

;; ── Evil keybindings ───────────────────────────────────────────
;; All handled by evil-collection — uses insert state so
;; i/a/A/I enter insert mode, ESC returns to normal state.
;; See evil-collection-vterm.el in the elpa directory.

;; ── Cursor snap ──────────────────────────────────────────────
;; After entering insert mode (i/I), send an ANSI "Report Cursor
;; Position" escape sequence (\e[6n) to the terminal. This forces
;; the terminal to respond, which triggers the vterm module to
;; re-evaluate its display, snapping the visual cursor to the
;; correct position immediately.
(defun my/vterm-snap-cursor (&rest _)
  "Snap the visual cursor by sending SPACE + BACKSPACE to the shell.
The shell echoes the space then deletes it with backspace, so
there is no visible effect. But the actual I/O forces the vterm
module to update the cursor display immediately, which is more
reliable than sending an ANSI escape that waits for the event loop.

Note: This may have side effects if a full-screen program (like
less, vim, htop) is active inside vterm when i/I is pressed,
since the space+backspace would be consumed by that program."
  (when (and (derived-mode-p 'vterm-mode)
             (bound-and-true-p vterm--process))
    (process-send-string vterm--process " \x7f")))

(with-eval-after-load 'evil-collection-vterm
  (advice-add 'evil-collection-vterm-insert :after #'my/vterm-snap-cursor)
  (advice-add 'evil-collection-vterm-insert-line :after #'my/vterm-snap-cursor))

;; ── Shell integration ──────────────────────────────────────────
;; Directory tracking: Emacs knows the shell's current directory.
;; The shell-side script is sourced in .bashrc:
;;
;;   if [[ "$INSIDE_EMACS" == "vterm" ]]; then
;;       source "${EMACS_VTERM_PATH%%\/libexec\/vterm*}/etc/emacs-vterm-bash.sh"
;;   fi

(provide 'vterm)
;; vterm.el ends here
