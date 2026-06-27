;; -*- lexical-binding: t; -*-
;;
;; wl-clipboard.el — Wayland clipboard for terminal Emacs

(when (and (eq window-system nil)
           (string= (or (getenv "XDG_SESSION_TYPE") "") "wayland")
           (executable-find "wl-copy")
           (executable-find "wl-paste"))

  (defun wl-copy (text)
    (when (stringp text)
      (with-temp-buffer
        (insert text)
        (call-process-region (point-min) (point-max)
                             "wl-copy" nil nil nil "-n"))))

  (defun wl-paste ()
    (let ((result (shell-command-to-string "wl-paste -n 2>/dev/null | tr -d '\\r'")))
      (unless (string-empty-p result)
        (decode-coding-string result 'utf-8))))

  (setq interprogram-cut-function #'wl-copy)
  (setq interprogram-paste-function #'wl-paste))

(provide 'wl-clipboard)
