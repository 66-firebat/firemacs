;; -*- lexical-binding: t; -*-
;;
;; =============================================================================
;;  dired.el — Dired customizations
;;
;;  - RET opens directories in the current buffer (instead of creating a new one)
;;  - ^ / - go up a directory in the current buffer
;;  - C-e toggles dired open/closed (defined in keybinds.el)
;; =============================================================================

(use-package dired
  :ensure nil
  :custom
  ;; -a: show hidden files (.git, etc.)
  ;; -l: use long listing format (shows size and date)
  ;; -h: human-readable sizes (e.g., 2K, 34M instead of raw bytes)
  ;; -g: omit owner name
  ;; -G: omit group name (in some ls versions, or use --no-group depending on OS)
  (dired-listing-switches "-alhgG"))

;; Enable `dired-find-alternate-file' (it's disabled by default because it's
;; "dangerous", but we use it intentionally to reuse the dired buffer).
(put 'dired-find-alternate-file 'disabled nil)

;; When copying/moving files, automatically suggest the adjacent dired buffer's
;; directory as the target (dwim = "do what I mean").
(setq dired-dwim-target t)

(defun my/dired-up-directory ()
  "Go up one directory, reusing the current dired buffer."
  (interactive)
  (find-alternate-file ".."))

;; ── Smart create: file or directory based on trailing / ──

(defun my/dired-create-file-or-dir ()
  "Create a new file or directory in the current Dired buffer.
Prompts for a name.  If the input ends with \"/\", creates a directory.
Otherwise creates an empty file."
  (interactive)
  (let* ((name (read-string "Create: "))
         (full (expand-file-name name default-directory)))
    (if (string-suffix-p "/" name)
        (dired-create-directory (directory-file-name name))
      (dired-create-empty-file name))))

;; ── Open file with system handler ──

(defun my/dired-xdg-open ()
  "Open the file at point with the system default application (xdg-open).
Directories are ignored with a message."
  (interactive)
  (let ((file (dired-get-filename)))
    (cond
     ((null file)
      (user-error "Not on a file line"))
     ((file-directory-p file)
      (message "Not a file: %s" (file-name-nondirectory file)))
     ((not (executable-find "xdg-open"))
      (user-error "xdg-open not found in PATH"))
     (t
      (start-process "dired-xdg-open" nil "xdg-open" file)
      (message "Opened: %s" (file-name-nondirectory file))))))

;; Use evil-define-key (via general-def) to override evil-collection's
;; bindings.  Plain define-key on dired-mode-map won't work because
;; evil-collection puts its bindings in evil auxiliary keymaps which
;; take priority over dired-mode-map.
;;
;; This runs after evil-collection-dired-setup because dired.el is
;; loaded after evil-collection in init.el, so our bindings win.
(general-def 'normal dired-mode-map
  "RET" 'dired-find-alternate-file
  "^"   'my/dired-up-directory
  "-"   'my/dired-up-directory
  "o"   'my/dired-create-file-or-dir
  "<S-return>" 'my/dired-xdg-open
  "s"   'my/consult-line-with-jump
  "S"   'my/consult-ripgrep-with-jump)

(provide 'dired-overrides)
;; dired.el ends here
