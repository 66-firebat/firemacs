;; -*- lexical-binding: t; -*-
;;
;; =============================================================================
;;  broot.el — Broot (terminal file manager) for Firemacs
;;
;;  `M-e' runs `my/broot-default-directory': a toggle that opens broot in the
;;  current window, rooted at the current buffer's `default-directory' — the
;;  broot analogue of `my/dired-default-directory' (keybinds.el).
;;
;;  Session model
;;  -------------
;;  - Per window: each window owns at most one broot session, recorded in the
;;    window parameter `my/broot-session' (the session's buffer).  This
;;    follows the per-window isolation philosophy used by MRU-tabs.el.
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
;;  - the `broot' binary on `exec-path'
;; =============================================================================

(declare-function ghostel-exec "ghostel.el" (buffer program &optional args))

(defvar my/broot-session-param 'my/broot-session
  "Window parameter key that stores a window's broot session buffer.
The value is the ghostel buffer running broot, or nil.")

(defvar my/broot-buffer-prefix "*broot*"
  "Buffer-name prefix used for new broot session buffers.
`generate-new-buffer' uniquifies (\"*broot*\", \"*broot*<2>\", ...).")

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
WINDOW defaults to the selected window.  A recorded buffer that is dead
or no longer in `ghostel-mode' is treated as no session (and forgotten)."
  (let* ((win (or window (selected-window)))
         (buf (window-parameter win my/broot-session-param)))
    (cond
     ((and (buffer-live-p buf)
           (with-current-buffer buf (derived-mode-p 'ghostel-mode)))
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
