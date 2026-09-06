;; -*- lexical-binding: t; -*-
;;
;; =============================================================================
;;  broot.el — Broot (terminal file manager) for Firemacs
;;
;;  `M-e' (`my/broot-default-directory') toggles a broot session in the current
;;  window, rooted at the current buffer's `default-directory' — the broot
;;  analogue of `my/dired-default-directory' (keybinds.el).
;;
;;  `M-z' routes through `my/zoxide-travel-dispatch' (keybinds.el):
;;    - plain Ghostel terminal  -> `ghostfire-travel' (cd the shell)
;;    - broot session / any other buffer -> `my/zoxide-travel-to-broot',
;;      which picks a directory from zoxide and opens a broot session rooted
;;      there, replacing the current window's broot session if one is open.
;;
;;  Session model
;;  -------------
;;  - Major mode: broot sessions run in `broot-mode', a major mode DERIVED
;;    from `ghostel-mode' (so ghostel's terminal machinery still applies and
;;    `derived-mode-p' checks for ghostel keep passing) but distinguishable
;;    from a plain terminal via `(derived-mode-p 'broot-mode)'.  The buffer is
;;    put in `broot-mode' BEFORE `ghostel-exec' spawns the process, because
;;    ghostel refuses major-mode changes while a terminal process is live.
;;  - Per window: each window owns at most one broot session, recorded in the
;;    window parameter `my/broot-session' (the session's buffer).  Follows the
;;    per-window isolation philosophy used by MRU-tabs.el.
;;  - A session is a Ghostel terminal whose process *is* broot (spawned with
;;    `ghostel-exec', no shell in between), so the buffer IS the broot
;;    session.  Quitting broot exits the process, and ghostel then auto-kills
;;    the buffer (`ghostel-kill-buffer-on-exit') — our local
;;    `kill-buffer-hook' drops the window parameter at the same time.
;;  - Toggle: M-e in a window that owns a live broot session closes it (kills
;;    the buffer, hence broot).  Otherwise a new session is spawned in the
;;    current window.  No return-to-previous-buffer bookkeeping — parity with
;;    `my/dired-default-directory'.
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

(defvar my/broot-session-param 'my/broot-session
  "Window parameter key that stores a window's broot session buffer.
The value is the `broot-mode' ghostel buffer running broot, or nil.")

(defvar my/broot-buffer-prefix "*broot*"
  "Buffer-name prefix used for new broot session buffers.
`generate-new-buffer' uniquifies (\"*broot*\", \"*broot*<2>\", ...).")

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

;; ── Window-parameter bookkeeping ─────────────────────────────────

(defun my/broot--forget-buffer (buffer)
  "Forget BUFFER in every window that references it as its broot session."
  (dolist (frame (frame-list))
    (dolist (win (window-list frame))
      (when (eq (window-parameter win my/broot-session-param) buffer)
        (set-window-parameter win my/broot-session-param nil)))))

(defun my/broot--on-kill ()
  "Buffer-local `kill-buffer-hook': drop this session from all windows."
  (my/broot--forget-buffer (current-buffer)))

(defun my/broot--session-buffer (&optional window)
  "Return WINDOW's live broot session buffer, or nil.
WINDOW defaults to the selected window.  A session is only considered open
when its buffer is live and in `broot-mode' (a plain Ghostel terminal never
qualifies).  A recorded buffer that fails those checks is forgotten."
  (let* ((win (or window (selected-window)))
         (buf (window-parameter win my/broot-session-param)))
    (cond
     ((and (buffer-live-p buf)
           (with-current-buffer buf (derived-mode-p 'broot-mode)))
      buf)
     (buf
      (set-window-parameter win my/broot-session-param nil)
      nil))))

;; ── Spawn ────────────────────────────────────────────────────────

(defun my/broot--open (dir)
  "Open a broot session rooted at DIR in the selected window.
Spawns broot as a Ghostel terminal process via `ghostel-exec' and records
the session buffer in the selected window's `my/broot-session' parameter.
Returns the session buffer."
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
              (broot-mode)
              (add-hook 'kill-buffer-hook #'my/broot--on-kill nil t))
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
            (set-window-parameter (selected-window) my/broot-session-param buf)
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
current window.  If the current window already owns a live broot session,
that session is replaced (killed) first — a quick \"reroot\" while browsing.

Callable from any buffer (e.g. M-x); the M-z dispatcher routes plain
Ghostel terminals to `ghostfire-travel' instead."
  (interactive)
  (ghostfire--check-deps)
  (let* ((win (selected-window))
         (candidate
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
      ;; Reroot: drop this window's live broot session, if any.
      (when-let ((session (my/broot--session-buffer win)))
        (kill-buffer session))
      (my/broot--open candidate))))

;; ── Command ──────────────────────────────────────────────────────

(defun my/broot-default-directory ()
  "Toggle a broot session in the current window at `default-directory'.

Parity with `my/dired-default-directory':
  - Broot starts at the current buffer's `default-directory' — no prompt.
  - If the current window already owns a live broot session, pressing M-e
    closes it: the session buffer (and thus the broot process) is killed.
  - No previous-buffer restoration after closing.

Quitting broot normally also ends the session: ghostel kills the buffer
when the process exits (`ghostel-kill-buffer-on-exit')."
  (interactive)
  (if-let ((session (my/broot--session-buffer)))
      (progn
        (kill-buffer session)
        (unless (buffer-live-p session)
          (message "broot closed")))
    (my/broot--open default-directory)))

(provide 'broot)
;; broot.el ends here
