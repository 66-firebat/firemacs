# eaterz-travel — Self-contained zoxide travel for eat terminals

**Target:** `eat/firemacs-eat.el` (new section after the dispatch block, before `(provide 'eat-firemacs)`)
**Status:** APPROVED — ready for implementation
**Date:** 2026-07-20

---

## Objective

Add `eaterz-travel` — a self-contained, namespaced clone of the zoxide +
consult + embark pipeline currently living in `zoxide.el` (as
`eat-zoxide-travel`) and `grease/plugins/greaszy.el` (as `greaszy-travel`).

`eaterz-travel` queries the zoxide database via consult's async completion,
lets the user select a directory, then sends `cd <dir> && clear` into the
current eat terminal.

It is a standalone implementation — it does **not** require `zoxide.el` or
`greaszy.el` to be loaded.  All zoxide, consult, embark, and vertico
plumbing is duplicated under the `eaterz-` / `eaterz--` namespace.

---

## Dispatch integration

The user has already updated `my/zoxide-travel-dispatch` in `keybinds.el`:

```elisp
(defun my/zoxide-travel-dispatch ()
  (interactive)
  (if (derived-mode-p 'eat-mode)
      (call-interactively #'eaterz-travel)
    (call-interactively #'greaszy-travel)))
```

So `eaterz-travel` is only called when already in an eat terminal buffer.
**No eat-mode guard is needed inside `eaterz-travel` itself.**

---

## Decisions from Q&A

| # | Topic | Decision |
|---|-------|----------|
| 1 | Namespace | `eaterz-` (public), `eaterz--` (private) |
| 2 | Embark keymap | Register `eaterz-embark-path-map` under `eaterz-path` category |
| 3 | Eat-mode guard inside function | Skip — dispatcher validates it |
| 4 | Zoxide executable | Inline `(executable-find "zoxide")`, no `defcustom` |
| 5 | Embark functions | Duplicate under `eaterz-`/`eaterz--` namespace |
| — | Fallbacks | None — `user-error` if any dependency is missing |
| — | File location | `eat/firemacs-eat.el`, after dispatch block |

---

## Dependency graph

```
eaterz-travel
  ├─ eaterz--check-deps
  │    ├─ (executable-find "zoxide")        ← user-error if missing
  │    ├─ (fboundp 'consult--read)          ← user-error if missing
  │    ├─ (featurep 'embark)                ← user-error if missing
  │    └─ (featurep 'vertico)               ← user-error if missing
  │
  ├─ consult--read (from consult)
  │    ├─ consult--process-collection
  │    │    └─ eaterz-consult-builder       → zoxide query -ls
  │    ├─ consult--async-map
  │    │    └─ eaterz-consult-format        → eaterz-parse-score-line
  │    │                                      eaterz-format-entry
  │    ├─ eaterz--async-wrap                → consult--async-pipeline
  │    ├─ eaterz-consult-map                → C-i: eaterz-embark-add
  │    │                                       C-d: eaterz-embark-subtract
  │    └─ :lookup → eaterz-parse-score-line
  │
  ├─ eat-term-parameter                     (from eat — already loaded)
  └─ eat--send-string                       (from eat — already loaded)
```

```
eaterz-embark-add
  ├─ eaterz--embark-extract-path            → vertico--candidate
  │                                          → eaterz-parse-score-line
  └─ eaterz--embark-refresh                 → eaterz--run, vertico internals
```

---

## Proposed implementation

### 1. Dependency guard

```elisp
(defun eaterz--check-deps ()
  "Signal `user-error' if any required dependency for `eaterz-travel' is missing."
  (unless (executable-find "zoxide")
    (user-error "Eaterz: `zoxide' binary not found on exec-path"))
  (unless (fboundp 'consult--read)
    (user-error "Eaterz: consult is required — install it with `M-x package-install RET consult RET'"))
  (unless (featurep 'embark)
    (user-error "Eaterz: embark is required — install it with `M-x package-install RET embark RET'"))
  (unless (featurep 'vertico)
    (user-error "Eaterz: vertico is required — install it with `M-x package-install RET vertico RET'"))
  t)
```

### 2. Custom variables

```elisp
(defcustom eaterz-show-scores t
  "When non-nil, display the frecency score to the left of each path.
When nil, only the path is shown (scores are still used for ranking)."
  :type 'boolean
  :group 'eat)

(defcustom eaterz-score-width 6
  "Width of the score field when displaying eaterz results.
The score is right-justified within this width."
  :type 'integer
  :group 'eat)

(defcustom eaterz-score-path-padding 4
  "Spaces between the score and the path in eaterz results."
  :type 'integer
  :group 'eat)

(defcustom eaterz-add-amount 5
  "Amount added to a directory's score on `eaterz-embark-add'.
Passed as `--score' to `zoxide add'."
  :type 'integer
  :group 'eat)

(defcustom eaterz-subtract-amount 5
  "Fixed amount subtracted on `eaterz-embark-subtract'.
The directory is removed and re-added at `max(1, current - this)'."
  :type 'integer
  :group 'eat)
```

### 3. Face

```elisp
(defface eaterz-score-face
  '((t (:inherit font-lock-comment-face)))
  "Face for the frecency score in eaterz results."
  :group 'eat)
```

### 4. Zoxide runner

```elisp
(defvar eaterz--executable (executable-find "zoxide")
  "Cached path to the `zoxide' binary, set at load time.")

(defun eaterz--run (async &rest args)
  "Run the `zoxide' command with ARGS.
If ASYNC is non-nil, launch asynchronously and return the process object.
Otherwise run synchronously and return stdout as a string, or nil on failure."
  (if async
      (apply #'start-process "eaterz" "*eaterz*" eaterz--executable args)
    (with-temp-buffer
      (if (equal 0 (apply #'call-process eaterz--executable nil t nil args))
          (buffer-string)
        (append-to-buffer "*eaterz*" (point-min) (point-max))
        (warn "Eaterz: zoxide error (see buffer *eaterz* for details)")
        nil))))
```

### 5. Score parsing & display

```elisp
(defun eaterz-parse-score-line (line)
  "Parse a single LINE from `zoxide query -ls' into (SCORE . PATH)."
  (let ((trimmed (string-trim line)))
    (when (string-match (rx (group (+ (or digit ?.)))
                            " "
                            (group (+ any)))
                        trimmed)
      (cons (string-to-number (match-string 1 trimmed))
            (string-trim (match-string 2 trimmed))))))

(defun eaterz-format-entry (score path &optional score-width padding)
  "Format an eaterz entry with SCORE right-justified before PATH."
  (if (not eaterz-show-scores)
      path
    (let* ((sw (or score-width eaterz-score-width))
           (pad (or padding eaterz-score-path-padding))
           (score-str (format (format "%%%d.1f" sw) score)))
      (concat
       (propertize score-str 'face 'eaterz-score-face)
       (make-string pad ?\s)
       path))))

(defun eaterz-consult-format (line)
  "Format a raw LINE from `zoxide query -ls' for consult display."
  (pcase (eaterz-parse-score-line line)
    (`(,score . ,path)
     (propertize (eaterz-format-entry score path)
                 'eaterz-score score
                 'eaterz-path path))
    (_ nil)))

(defun eaterz-consult-builder (input)
  "Build command line for `zoxide query -ls' from INPUT."
  (if (or (not input) (string-empty-p input))
      (list eaterz--executable "query" "-ls")
    (list eaterz--executable "query" "-ls" input)))
```

### 6. Consult async wrapper

```elisp
(defun eaterz--async-wrap (async)
  "Wrap ASYNC function for eaterz consult pipeline."
  (consult--async-pipeline
   async
   (consult--async-indicator)
   (consult--async-refresh)))
```

### 7. Minibuffer keymap

```elisp
(defvar-keymap eaterz-consult-map
  :doc "Additional keybindings for the eaterz travel minibuffer."
  "C-i" #'eaterz-embark-add
  "C-d" #'eaterz-embark-subtract)
```

### 8. Embark actions

```elisp
(defun eaterz--embark-extract-path (&optional candidate)
  "Extract the path from a vertico candidate."
  (unless candidate
    (setq candidate (vertico--candidate))
    (when (and candidate (fboundp 'consult--tofu-strip))
      (setq candidate (consult--tofu-strip candidate))))
  (or (cdr (eaterz-parse-score-line candidate)) candidate))

(defun eaterz--embark-refresh ()
  "Re-query zoxide and replace `vertico--candidates' in place."
  (let* ((input (minibuffer-contents-no-properties))
         (args (if (or (not input) (string-empty-p input))
                   '("query" "-ls")
                 `("query" "-ls" ,input)))
         (raw (apply #'eaterz--run nil args))
         (lines (and raw (remove "" (split-string raw "\n" t))))
         (new-candidates (delq nil (mapcar #'eaterz-consult-format lines))))
    (when (and (boundp 'vertico--candidates) vertico--candidates)
      (setq vertico--candidates new-candidates
            vertico--total (length vertico--candidates))
      (if (zerop vertico--total)
          (setq vertico--index -1)
        (when (>= vertico--index vertico--total)
          (setq vertico--index (max 0 (1- vertico--total)))))
      (vertico--prompt-selection)
      (vertico--display-count)
      (vertico--display-candidates (vertico--arrange-candidates)))))

(defun eaterz-embark-add (&optional candidate)
  "Boost the frecency score of the selected zoxide directory."
  (interactive)
  (setq candidate (eaterz--embark-extract-path candidate))
  (when candidate
    (eaterz--run nil "add" "--score"
                 (number-to-string eaterz-add-amount) candidate)
    (eaterz--embark-refresh)
    (message "Eaterz: %s +%d" candidate eaterz-add-amount))
  candidate)

(defun eaterz-embark-subtract (&optional candidate)
  "Remove the selected directory from the zoxide database."
  (interactive)
  (setq candidate (eaterz--embark-extract-path candidate))
  (when candidate
    (eaterz--run nil "remove" candidate)
    (eaterz--embark-refresh)
    (message "Eaterz: %s removed" candidate))
  candidate)
```

### 9. Embark keymap registration

```elisp
(with-eval-after-load 'embark
  (defvar-keymap eaterz-embark-path-map
    :doc "Keymap for embark actions on eaterz-path candidates."
    :parent embark-general-map
    "+" #'eaterz-embark-add
    "-" #'eaterz-embark-subtract)

  (add-to-list 'embark-keymap-alist '(eaterz-path . eaterz-embark-path-map)))
```

### 10. Main entry point

```elisp
(defun eaterz-travel ()
  "Select a zoxide directory and cd to it in the current eat terminal.
Queries the zoxide database via consult's async completion, showing
frecency scores.  On selection, sends `cd <dir> && clear' to the
shell process of the current eat terminal.

Requires consult, embark, and vertico.  The `zoxide' binary must be
on `exec-path'.  Signals `user-error' if any dependency is missing.

This function assumes the caller has already verified we are in an
eat terminal buffer (the dispatcher guarantees this)."
  (interactive)
  (eaterz--check-deps)
  (let* ((origin-buffer (current-buffer))
         (candidate
          (consult--read
           (consult--process-collection #'eaterz-consult-builder
             :transform (consult--async-map #'eaterz-consult-format))
           :async-wrap #'eaterz--async-wrap
           :keymap eaterz-consult-map
           :prompt "󰡦 : "
           :category 'eaterz-path
           :require-match t
           :sort nil
           :lookup (lambda (selected &rest _)
                     (when selected
                       (or (cdr (eaterz-parse-score-line selected))
                           selected))))))
    (when (and candidate (buffer-live-p origin-buffer))
      (with-current-buffer origin-buffer
        (when-let ((proc (eat-term-parameter eat-terminal 'eat--process)))
          (eat--send-string proc (format "cd %s && clear\n" candidate))
          (message "Eaterz: cd to %s" candidate))))
    candidate))
```

---

## file placement in `eat/firemacs-eat.el`

All eaterz code goes after the existing dispatch block and before `(provide 'eat-firemacs)`:

```
;; ── Dispatch ────────────────────────────────────────────────────
(defvar my/eat-new-dispatch-alist ...)
(defun my/eat-new-from-grease ...)
(defun my/eat-new-dispatch ...)

;; ── Eaterz ── Zoxide travel for eat terminals ──────────────────
;; ... all eaterz code ...

(provide 'eat-firemacs)
```

---

## questions

### A. `eaterz-embark-path-map` — wrap or not?  ✅

**Decision: A** — wrap the keymap definition + registration in
`(with-eval-after-load 'embark ...)`.  The keymap is deferred until embark
loads, which is safe regardless of init load order.

### B. `executable-find` — call inline or cache?  ✅

**Decision: B** — cache the result in a `defvar` set at load time.
One fewer syscall per invocation.

### C. `eaterz-subtract-amount` — keep, drop, or fully implement?  ✅

**Decision: A** — keep the var and the `zoxide remove` behavior, matching
greaszy as-is.  The re-add-at-lower-score logic is a future enhancement.

### D. Byte-compilation warnings for eat internals  ✅

**Decision: C** — do nothing.  The user does not byte-compile their config;
the warnings are never emitted.

### E. `eaterz-travel` — guard for eat process?  ✅

**Decision: B** — `user-error` ("No active process in this eat terminal")
so the user knows why nothing happened instead of a silent no-op.

### F. `eaterz-path` vs `greaszy-path` — distinct completion categories?  ✅

**Decision: keep them separate.**  The files and functionalities should be
completely independent — distinct categories, distinct embark keymaps,
no cross-dependencies.
