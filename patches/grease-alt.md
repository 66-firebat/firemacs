# PATCH — Grease alt-visit: `Shift + Enter`

## Goal

Add `Shift + Enter` in grease buffers to open files/directories with alternative, non-default actions. Unlike `RET` (`grease-visit`) which closes the grease buffer when opening files, `grease-visit-alt` keeps the grease buffer open in both cases.

| Entry type | `RET` (grease-visit) | `Shift+Enter` (grease-visit-alt) |
|-----------|----------------------|----------------------------------|
| File | Kills grease buffer, opens in Emacs | Keeps buffer open, calls `grease-visit-alt-file-callback` (default: async `xdg-open`) |
| Directory | Renders directory in-place in grease | Calls `grease-visit-alt-directory-callback` (default: new eat terminal in same window, cd to that dir). Grease view unchanged. |

## Decisions

| Question | Answer |
|----------|--------|
| Eat placement | Same window, replaces grease |
| Grease view after dir visit | Unchanged — don't navigate into the directory |
| `xdg-open` | Async (`start-process`), no blocking |
| Commit prompt | Skip — buffer stays open, no need |

## Proposed implementation

### 1. Defcustoms (in `grease.el`)

```elisp
(defcustom grease-visit-alt-file-callback
  (lambda (path) (start-process "xdg-open" nil "xdg-open" path))
  "Callback for `grease-visit-alt' when visiting a file.
Receives the full filesystem path as a single string argument."
  :type 'function
  :group 'grease)

(defcustom grease-visit-alt-directory-callback
  (lambda (dir)
    (let ((default-directory dir))
      (call-interactively #'eat)))
  "Callback for `grease-visit-alt' when visiting a directory.
Receives the full directory path as a single string argument.
Default: opens a new eat terminal in the current window at that directory."
  :type 'function
  :group 'grease)
```

### 2. `grease-visit-alt` function (in `grease.el`)

```elisp
(defun grease-visit-alt ()
  "Visit file or directory at point with alternative callback.
Files: calls `grease-visit-alt-file-callback' (keeps buffer open).
Directories: calls `grease-visit-alt-directory-callback'."
  (interactive)
  (let ((data (grease--get-line-data)))
    (if (not data)
        (user-error "Not on a file or directory line.")
      (let* ((name (plist-get data :name))
             (type (plist-get data :type))
             (path (grease--get-full-path name)))
        (if (eq type 'dir)
            (progn
              (unless grease-visit-alt-directory-callback
                (user-error "grease-visit-alt-directory-callback not defined"))
              (funcall grease-visit-alt-directory-callback path))
          (unless grease-visit-alt-file-callback
            (user-error "grease-visit-alt-file-callback not defined"))
          (funcall grease-visit-alt-file-callback path))))))
```

### 3. Keybinding (in `grease.el`)

Add to the `evil-define-key* 'normal grease-mode-map` block:

```elisp
(kbd "<S-return>") #'grease-visit-alt
```

## Tests (in `grease/grease-test.el`)

```elisp
;;;; grease-visit-alt Tests

(ert-deftest grease-test-visit-alt-not-on-entry ()
  "Error when not on a file or directory line."
  (grease-test-with-temp-dir
    (write-region "" nil (expand-file-name "file.txt" temp-dir))
    (grease-test-with-buffer temp-dir
      (goto-char (point-min))  ;; header line
      (should-error (grease-visit-alt)
                    :type 'user-error))))

(ert-deftest grease-test-visit-alt-file-calls-callback ()
  "Shift+Enter on a file calls the file callback with the full path."
  (let ((called-path nil))
    (grease-test-with-temp-dir
      (write-region "hello" nil (expand-file-name "file.txt" temp-dir))
      (grease-test-with-buffer temp-dir
        (let ((grease-visit-alt-file-callback
               (lambda (path) (setq called-path path))))
          (grease-test-goto-entry "file.txt")
          (grease-visit-alt)
          (should (equal called-path
                         (expand-file-name "file.txt" temp-dir))))))))

(ert-deftest grease-test-visit-alt-file-keeps-buffer-open ()
  "Visiting a file with Shift+Enter should keep the grease buffer alive."
  (grease-test-with-temp-dir
    (write-region "" nil (expand-file-name "file.txt" temp-dir))
    (grease-test-with-buffer temp-dir
      (let ((grease-visit-alt-file-callback (lambda (_) nil))
            (buf (current-buffer)))
        (grease-test-goto-entry "file.txt")
        (grease-visit-alt)
        (should (buffer-live-p buf))))))

(ert-deftest grease-test-visit-alt-file-default-is-xdg-open ()
  "Default file callback opens xdg-open asynchronously."
  (grease-test-with-temp-dir
    (write-region "" nil (expand-file-name "file.txt" temp-dir))
    (grease-test-with-buffer temp-dir
      (let* ((called-args nil)
             (grease-visit-alt-file-callback
              (lambda (path) (setq called-args (list "xdg-open" path)))))
        (grease-test-goto-entry "file.txt")
        (grease-visit-alt)
        (should (equal (car called-args) "xdg-open"))
        (should (equal (cadr called-args)
                       (expand-file-name "file.txt" temp-dir)))))))

(ert-deftest grease-test-visit-alt-directory-calls-callback ()
  "Shift+Enter on a directory calls the directory callback."
  (let ((called-dir nil))
    (grease-test-with-temp-dir
      (make-directory (expand-file-name "subdir" temp-dir))
      (grease-test-with-buffer temp-dir
        (let ((grease-visit-alt-directory-callback
               (lambda (dir) (setq called-dir dir))))
          (grease-test-goto-entry "subdir")
          (grease-visit-alt)
          (should (equal called-dir
                         (expand-file-name "subdir" temp-dir))))))))

(ert-deftest grease-test-visit-alt-directory-default-navigates ()
  "Default directory callback renders the directory in-place."
  (grease-test-with-temp-dir
    (make-directory (expand-file-name "subdir" temp-dir))
    (write-region "inside" nil (expand-file-name "subdir/inner.txt" temp-dir))
    (grease-test-with-buffer temp-dir
      (grease-test-goto-entry "subdir")
      (grease-visit-alt)
      ;; Default callback is grease--render — should now show subdir contents
      (should (string-match-p "inner.txt" (buffer-string))))))

(ert-deftest grease-test-visit-alt-file-callback-not-defined ()
  "Error when file callback is nil."
  (grease-test-with-temp-dir
    (write-region "" nil (expand-file-name "file.txt" temp-dir))
    (grease-test-with-buffer temp-dir
      (let ((grease-visit-alt-file-callback nil))
        (grease-test-goto-entry "file.txt")
        (should-error (grease-visit-alt)
                      :type 'user-error)))))

(ert-deftest grease-test-visit-alt-directory-callback-not-defined ()
  "Error when directory callback is nil."
  (grease-test-with-temp-dir
    (make-directory (expand-file-name "subdir" temp-dir))
    (grease-test-with-buffer temp-dir
      (let ((grease-visit-alt-directory-callback nil))
        (grease-test-goto-entry "subdir")
        (should-error (grease-visit-alt)
                      :type 'user-error)))))
```
