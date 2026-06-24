;; -*- lexical-binding: t; -*-
;;
;; =============================================================================
;;  jumpring.el — Global jump ring for Evil
;;
;;  Makes ALL windows share the same jump list by modifying Evil's per-window
;;  hash table directly.  C-o / C-i navigate the same history everywhere.
;; =============================================================================

(defvar jr--global-struct nil
  "Single evil-jumps-struct shared by all windows.")

(defun jr--ensure-struct ()
  "Return the global jump struct, creating it if needed."
  (unless (and jr--global-struct
               (evil-jumps-struct-ring jr--global-struct))
    (setq jr--global-struct
          (make-evil-jumps-struct
           :ring (make-ring (or (bound-and-true-p evil-jumps-max-length) 100))
           :idx -1)))
  jr--global-struct)

(defun jr--populate-hash-table ()
  "Point every window in `evil--jumps-window-jumps' to the global struct."
  (let ((struct (jr--ensure-struct)))
    (dolist (w (window-list))
      (puthash w struct evil--jumps-window-jumps))))

;; ═════════════════════════════════════════════════════════════════════════════
;;  Advice — replace per-window logic
;; ═════════════════════════════════════════════════════════════════════════════

(advice-add 'evil--jumps-get-current :override
            (lambda (&optional _window)
              (jr--ensure-struct)))

(advice-add 'evil--jumps-window-configuration-hook :override
            (lambda (&rest _) nil))

;; ═════════════════════════════════════════════════════════════════════════════
;;  Savehist — load/save from the global struct
;; ═════════════════════════════════════════════════════════════════════════════

(advice-add 'evil--jumps-savehist-load :override
            (lambda ()
              (let ((ring (make-ring (or (bound-and-true-p evil-jumps-max-length) 100))))
                (cl-loop for jump in (reverse (bound-and-true-p evil-jumps-history))
                         do (ring-insert ring jump))
                (setf (evil-jumps-struct-ring (jr--ensure-struct)) ring))))

(advice-add 'evil--jumps-savehist-sync :override
            (lambda ()
              (setq evil-jumps-history
                    (delq nil
                          (mapcar
                           (lambda (jump)
                             (let* ((mark (car jump))
                                    (pos (if (markerp mark) (marker-position mark) mark))
                                    (file-name (cadr jump)))
                               (when (and (not (file-remote-p file-name))
                                          (file-exists-p file-name)
                                          pos)
                                 (list pos file-name))))
                           (ring-elements (evil--jumps-get-jumps (jr--ensure-struct))))))))

;; ═════════════════════════════════════════════════════════════════════════════
;;  Fix: ensure jumps in non-file buffers (eat, scratch, etc.) are saved
;; ═════════════════════════════════════════════════════════════════════════════

;; evil--jumps-push silently drops jumps when buffer-file-name is nil AND
;; the buffer name doesn't match the *scratch*/*new* regex. This breaks
;; jump tracking in eat terminals and other non-file buffers.
(advice-add 'evil--jumps-push :around
            (lambda (orig-fn)
              (cl-letf (((symbol-function 'evil--jumps-current-file-name)
                         (lambda ()
                           (or buffer-file-name
                               (when (derived-mode-p 'dired-mode)
                                 default-directory)
                               (buffer-name (current-buffer))))))
                (funcall orig-fn))))

;; Fix: when jumping back, evil--jumps-jump calls find-file with the stored
;; file-name. For non-file buffers (eat terminals), file-name is the buffer
;; name — find-file would fail.  Check for live buffers first.
(advice-add 'evil--jumps-jump :around
            (lambda (orig-fn idx shift)
              (let ((orig-find-file (symbol-function 'find-file)))
                (cl-letf (((symbol-function 'find-file)
                           (lambda (filename &optional wildcards)
                             (if (get-buffer filename)
                                 (switch-to-buffer filename)
                               (funcall orig-find-file filename wildcards)))))
                  (funcall orig-fn idx shift)))))

(defun jr--on-window-config-change ()
  "Ensure new windows also point to the global struct."
  (when (bound-and-true-p evil--jumps-window-jumps)
    (jr--populate-hash-table)))

(advice-add 'evil--jumps-window-configuration-hook :override
            #'jr--on-window-config-change)

;; ═════════════════════════════════════════════════════════════════════════════
;;  Initialize — populate the hash table immediately
;; ═════════════════════════════════════════════════════════════════════════════

(defun jr--init ()
  "Initialize the global jump ring."
  (when (and (boundp 'evil--jumps-window-jumps)
             (fboundp 'make-evil-jumps-struct))
    (jr--populate-hash-table)))

;; Delay init slightly to ensure Evil is fully loaded
(if (and (boundp 'evil--jumps-window-jumps)
         (fboundp 'make-evil-jumps-struct))
    (jr--init)
  (with-eval-after-load 'evil-jumps
    (jr--init)))

(provide 'jumpring)
;; jumpring.el ends here
