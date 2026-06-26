# Emacs Lisp Balance Checker

## Robust Paren/Quote Checker

```bash
cp /path/to/your/file.el /tmp/generated_code.el && emacs --batch --load /dev/stdin 2>&1 <<-'EMACSCODE'
  (let ((fn "/tmp/generated_code.el"))
    (unless (file-exists-p fn)
      (error "File not found: %s" fn))
    (find-file fn)
    (let ((stack nil) (ok t) (err-msg nil) (err-pos nil))
      (save-excursion
        (goto-char (point-min))
        (while (and ok (< (point) (point-max)))
          (let ((ppss (syntax-ppss)))
            (cond
             ;; Inside string — skip to end
             ((nth 3 ppss)
              (if (re-search-forward "\\([^\\]\\|\\`\\)\"" nil t)
                  (forward-char 0)
                (setq ok nil err-msg "Unterminated string" err-pos (point))))
             ;; Inside comment — skip line
             ((nth 4 ppss)
              (forward-line 1))
             ;; Open paren
             ((eq (char-after) ?\()
              (push (point) stack)
              (forward-char 1))
             ;; Open bracket
             ((eq (char-after) ?\[)
              (push (cons (point) 'vector) stack)
              (forward-char 1))
             ;; Close paren
             ((eq (char-after) ?\))
              (if (null stack)
                  (setq ok nil err-msg "Extra )" err-pos (point))
                (let ((top (pop stack)))
                  (when (consp top)
                    (setq ok nil err-msg "Mismatched: ] without matching ["
                          err-pos (point)))))
              (forward-char 1))
             ;; Close bracket
             ((eq (char-after) ?\])
              (if (null stack)
                  (setq ok nil err-msg "Extra ]" err-pos (point))
                (let ((top (pop stack)))
                  (unless (consp top)
                    (setq ok nil err-msg "Mismatched: ) without matching ("
                          err-pos (point)))))
              (forward-char 1))
             ;; Quote
             ((eq (char-after) ?\')
              (let ((start (point)))
                (forward-char 1)
                (skip-syntax-forward "'")
                (condition-case nil
                    (when (memq (char-after) '(?\( ?\[ ?\`))
                      (forward-sexp 1))
                  (error
                   (setq ok nil err-msg "Stray quote" err-pos start)))))
             ;; Backquote
             ((eq (char-after) ?\`)
              (push (cons (point) 'backquote) stack)
              (forward-char 1))
             ;; Comma inside backquote
             ((eq (char-after) ?,)
              (let ((start (point)))
                (forward-char 1)
                (condition-case nil
                    (forward-sexp 1)
                  (error
                   (setq ok nil err-msg "Stray comma" err-pos start)))))
             (t (forward-char 1))))))
      (if ok
          ;; Check for unclosed
          (if stack
              (let ((top (car (last stack))))
                (setq err-pos (if (consp top) (car top) top))
                (setq err-msg "Unclosed opening paren/bracket/backquote"))
            (message "All balanced!")))
      (when err-msg
        (let ((line (line-number-at-pos err-pos))
              (col (save-excursion (goto-char err-pos) (1+ (current-column)))))
          (message "ERROR: %s at line %d, col %d (char pos %d)"
                   err-msg line col err-pos)
          (goto-char err-pos)
          (let ((start (max (point-min) (- err-pos 25)))
                (end (min (point-max) (+ err-pos 25))))
            (message "Context: %s"
                     (replace-regexp-in-string "\n" "\\\\n"
                       (buffer-substring start end))))))))
EMACSCODE
```

## Usage

```bash
cp /home/fireshark/fire_profile/configuration_modules/emacs/centaur-tabs.el /tmp/generated_code.el
# Then run the command above
```
