;; -*- lexical-binding: t; -*-
;;
;; =============================================================================
;;  broot.el — Broot (terminal file manager) for Firemacs
;;
;;  `M-e' (`my/broot-default-directory') toggles a broot session rooted at
;;  `default-directory'.  The toggle is BUFFER-based: if the current buffer is
;;  a broot session (in `broot-mode') it is closed; otherwise a new session is
;;  opened.  No session uniqueness is enforced, so several broot buffers can
;;  be open at once — the broot analogue of `my/dired-default-directory'
;;  (keybinds.el).
;;
;;  `M-z' routes through `my/zoxide-travel-dispatch' (keybinds.el):
;;    - plain Ghostel terminal  -> `ghostfire-travel' (cd the shell)
;;    - broot session / any other buffer -> `my/zoxide-travel-to-broot',
;;      which picks a directory from zoxide and opens a broot session rooted
;;      there.  When invoked from inside a broot session, that session is
;;      replaced (rerooted); other broot sessions are left untouched.
;;
;;  Session model
;;  -------------
;;  - Major mode: broot sessions run in `broot-mode', a major mode DERIVED
;;    from `ghostel-mode' (so ghostel's terminal machinery still applies and
;;    `derived-mode-p' checks for ghostel keep passing) but distinguishable
;;    from a plain terminal via `(derived-mode-p 'broot-mode)'.  The buffer is
;;    put in `broot-mode' BEFORE `ghostel-exec' spawns the process, because
;;    ghostel refuses major-mode changes while a terminal process is live.
;;  - A session is a Ghostel terminal whose process *is* broot (spawned with
;;    `ghostel-exec', no shell in between), so the buffer IS the broot
;;    session.  Quitting broot exits the process, and ghostel then auto-kills
;;    the buffer (`ghostel-kill-buffer-on-exit').
;;  - Sessions are ordinary buffers: they live in whichever window shows
;;    them, may be opened in any number of windows, and closing one never
;;    touches the others.
;;
;;  Selection wiring
;;  ----------------
;;  broot remains fully interactive.  Selecting a text file (Enter) runs the
;;  `edit' verb from ~/.config/broot/verbs.hjson — `emacsclient -n +{line}
;;  {file}' — which opens the file in the running Emacs (leave_broot: true).
;;  Because the session runs broot directly (no shell wrapper), broot inherits
;;  Emacs' environment, so emacsclient resolves against the live server.
;;  Directories keep their default broot behavior (navigate).  Future work can
;;  add verbs that hand paths back to Emacs for Dired/Grease etc.
;;
;;  Dependencies
;;  ------------
;;  - ghostel (declared and loaded via ghostel/ghostfire.el)
;;  - ghostfire (ghostel/ghostfire.el) for the shared consult/zoxide pipeline
;;  - the `broot' binary on `exec-path'
;; =============================================================================

(declare-function ghostel-mode "ghostel.el" ())
(declare-function ghostel-exec "ghostel.el" (buffer program &optional args))
(declare-function ghostfire--check-deps "ghostfire.el" ())
(declare-function ghostfire-consult-builder "ghostfire.el" (input))
(declare-function ghostfire-consult-format "ghostfire.el" (line))
(declare-function ghostfire-parse-score-line "ghostfire.el" (line))
(declare-function ghostfire--async-wrap "ghostfire.el" (async))
(declare-function consult--read "consult.el" (&rest args))
(declare-function consult--process-collection "consult.el" (&rest args))
(declare-function consult--async-map "consult.el" (&rest args))

(defvar ghostfire-consult-map nil
  "Keymap used in the ghostfire zoxide travel minibuffer (defined in ghostfire.el).")

(defvar my/broot-buffer-prefix "*broot*"
  "Buffer-name prefix used for new broot session buffers.
`generate-new-buffer' uniquifies (\"*broot*\", \"*broot*<2>\", ...), which
is what allows several broot sessions to be open at once.")

;; ── Major mode ───────────────────────────────────────────────────

(define-derived-mode broot-mode ghostel-mode "Broot"
  "Major mode for a broot session: a Ghostel terminal whose process is broot.

Derived from `ghostel-mode' so all of ghostel's terminal machinery
(renderer, PTY, semi-char input, kill handling) applies, while
`derived-mode-p' distinguishes a broot session from a plain Ghostel
terminal.  The mode is established on the session buffer BEFORE the broot
process is spawned (`ghostel-exec'); ghostel refuses major-mode changes
once a terminal process is live."
  ;; Broot-specific buffer setup can be added here as the feature grows.
  )

;; ── Spawn ────────────────────────────────────────────────────────

(defun my/broot--open (dir)
  "Open a broot session rooted at DIR in the current window.
Spawns broot as a Ghostel terminal process via `ghostel-exec' and returns
the new `broot-mode' session buffer."
  (require 'ghostel nil t)            ; ghostel-exec is not autoloaded
  (let* ((broot-exe (executable-find "broot"))
         (dir (file-name-as-directory (expand-file-name dir))))
    (unless broot-exe
      (user-error
       "broot: binary not found on `exec-path' (install the nixpkgs `broot' package)"))
    (unless (fboundp 'ghostel-exec)
      (user-error "broot: `ghostel-exec' unavailable — ghostel is not installed"))
    (let ((buf (generate-new-buffer my/broot-buffer-prefix)))
      (condition-case err
          (progn
            (with-current-buffer buf
              (setq default-directory dir)
              ;; Establish broot-mode (derived from ghostel-mode) BEFORE the
              ;; process spawn; ghostel blocks mode changes on live buffers.
              (broot-mode))
            ;; Display in the current window first so ghostel sizes the
            ;; terminal against it (same order `ghostel--create' uses).
            (pop-to-buffer buf (append display-buffer--same-window-action
                                       '((category . comint))))
            (ghostel-exec buf broot-exe nil)
            ;; The statuscolumn line-prefix eats 7 columns; force ghostel to
            ;; account for it (mirrors ghostfire's spawn-time correction).
            (when (fboundp 'ghostel--adjust-size)
              (let ((win (get-buffer-window buf t)))
                (when win
                  (ghostel--adjust-size win t))))
            (message "broot: %s" dir)
            buf)
        ((error quit)
         (when (buffer-live-p buf)
           (kill-buffer buf))
         (signal (car err) (cdr err)))))))

;; ── Zoxide travel ────────────────────────────────────────────────

(defun my/zoxide-travel-to-broot ()
  "Select a directory from zoxide and open a broot session rooted there.
Uses the same consult-based zoxide pipeline as `ghostfire-travel' (shared
builder, formatter, keymap, and prompt; embark +/− frecency actions work).

The selected directory becomes the root of a new broot session in the
current window.  When invoked from inside a broot session, that session is
replaced (killed) first — a quick \"reroot\" while browsing; any other
open broot sessions are left untouched.

Callable from any buffer (e.g. M-x); the M-z dispatcher routes plain
Ghostel terminals to `ghostfire-travel' instead."
  (interactive)
  (ghostfire--check-deps)
  (let ((candidate
         (consult--read
          (consult--process-collection #'ghostfire-consult-builder
            :transform (consult--async-map #'ghostfire-consult-format))
          :async-wrap #'ghostfire--async-wrap
          :keymap ghostfire-consult-map
          :prompt "󰡦 : "
          :category 'ghostfire-path
          :require-match t
          :sort nil
          :lookup (lambda (selected &rest _)
                    (when selected
                      (or (cdr (ghostfire-parse-score-line selected))
                          selected))))))
    (when candidate
      ;; Reroot: when we are inside a broot session, replace it.
      (when (derived-mode-p 'broot-mode)
        (kill-buffer (current-buffer)))
      (my/broot--open candidate))))

;; ── Command ──────────────────────────────────────────────────────

(defun my/broot-default-directory ()
  "Toggle a broot session at the current buffer's `default-directory'.

If the current buffer is a broot session (in `broot-mode'), close it:
the session buffer — and therefore the broot process — is killed.
Otherwise, open a new broot session rooted at `default-directory' with no
prompt.

Parity with `my/dired-default-directory':
  - Opening always spawns a fresh session in the current window; there is
    no uniqueness or focus-existing logic, so multiple broot buffers can
    be open at once.
  - Closing just kills the current broot buffer: no previous-buffer
    restoration, and if the buffer is shown in several windows it closes
    everywhere.
  - Quitting broot normally also ends the session: ghostel kills the
    buffer when the process exits (`ghostel-kill-buffer-on-exit')."
  (interactive)
  (if (derived-mode-p 'broot-mode)
      (when (kill-buffer (current-buffer))
        (message "broot closed"))
    (my/broot--open default-directory)))

(provide 'broot)
;; broot.el ends here
