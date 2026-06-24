;; -*- lexical-binding: t; -*-
;;
;; =============================================================================
;;  doom-modeline.el — Doom Modeline Customization
;;
;;  A clean, informative mode line with Nerd Font icons.
;;  Shows the absolute line number before the buffer name.
;; =============================================================================

;; ── Modeline setup ───────────────────────────────────────

;; Nerd Icons font — required by doom-modeline for mode line icons
(use-package nerd-icons
  :commands nerd-icons-install-fonts
  :config
  (setq nerd-icons-font-family "Symbols Nerd Font Mono"))

(use-package doom-modeline
  :demand t
  :config
  (doom-modeline-mode 1)
  ;; Helper: git diff stats string
  (defun my/gitsigns-str ()
    "Return git diff stats: 󰐗 N 󱍷 M 󰅙 K, or 󰵚 for non-VC buffers.
Parses the full diff at hunk level so modifications are counted
as changes, not split into insertions+deletions."
    (if (or (not buffer-file-name)
            (not (ignore-errors (vc-backend buffer-file-name))))
        "󰵚"
      (condition-case nil
          (let* ((file buffer-file-name)
                 (default-directory (file-name-directory file))
                 (inserts 0) (changes 0) (deletes 0))
            (with-temp-buffer
              (call-process "git" nil t nil "diff" "--" file)
              (goto-char (point-min))
              ;; Walk through each hunk
              (while (re-search-forward "^@@ " nil t)
                (forward-line)
                (let ((hunk-inserts 0) (hunk-deletes 0))
                  (while (and (not (eobp))
                              (not (looking-at "^@@")))
                    (cond ((looking-at "^\\+") (cl-incf hunk-inserts))
                          ((looking-at "^-")   (cl-incf hunk-deletes)))
                    (forward-line))
                  (cond ((and (> hunk-inserts 0) (> hunk-deletes 0))
                         (cl-incf changes))           ;; modification hunk
                        ((> hunk-deletes 0)
                         (cl-incf deletes hunk-deletes))  ;; pure deletion
                        ((> hunk-inserts 0)
                         (cl-incf inserts hunk-inserts))))))  ;; pure insertion
            (if (> (+ inserts changes deletes) 0)
                (format "󰐗 %d 󱍷 %d 󰅙 %d" inserts changes deletes)
              "󰵚"))
        (error "󰵚"))))

  ;; Git diff stats segment
  (doom-modeline-def-segment my-gitsigns
    "Git diff stats:  N  M  K"
    (let ((str (my/gitsigns-str)))
      (when str
        (concat (doom-modeline-spc) str))))

  ;; Terminal-friendly tweaks
  (setq doom-modeline-height 1)
  (setq doom-modeline-bar-width 1)
  (setq doom-modeline-major-mode-icon t)
  (setq doom-modeline-minor-modes nil)
  (setq doom-modeline-enable-word-count nil)
  (setq doom-modeline-buffer-encoding nil)
  (setq doom-modeline-indent-info nil)
  (setq doom-modeline-env-version t)
  (setq doom-modeline-github nil)
  ;; Custom buffer-info: buffer name followed by state icon.
  ;; Mode icon (/) removed — you already know what mode you're in.
  (doom-modeline-def-segment my-buffer-info
    "Buffer name with state icon after the name, no mode icon."
    (concat
     (doom-modeline-spc)
     (doom-modeline--buffer-name)
     " "
     (doom-modeline--buffer-state-icon)))

  ;; Redefine the main modeline.
  (doom-modeline-def-modeline 'main
    '(eldoc bar window-state workspace-name window-number
            modals matches follow my-buffer-info my-gitsigns remote-host)
    '(compilation objed-state misc-info project-name persp-name
                  battery grip irc mu4e gnus github debug repl
                  minor-modes input-method indent-info buffer-encoding
                  process check time))
  ;; Apply the redefined modeline
  (doom-modeline-set-modeline 'main t))

(provide 'doom-modeline)
;; doom-modeline.el ends here
