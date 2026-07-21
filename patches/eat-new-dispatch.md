# eat-new-dispatch — Mode-aware M-t dispatcher for `my/eat-new`

**Targets:**
- `eat/firemacs-eat.el` — new dispatcher, alist, handler(s), modified `my/eat-new`
- `keybinds.el` — rebind `M-t` from `my/eat-new` → `my/eat-new-dispatch`
- `eat/firemacs-eat.el` `eat-semi-char-non-bound-keys` block — no change needed (M-t still passes through to Emacs)

**Status:** APPROVED — ready for implementation
**Date:** 2026-07-20

---

## Objective

Replace the direct `M-t` → `my/eat-new` binding with a mode-aware dispatcher.
When in a `grease-mode` buffer, the terminal spawns in `grease--root-dir`.
In every other mode, fall through to the existing `my/eat-new` behavior.
The dispatch mechanism uses a pure alist for future extensibility.

---

## Q&A decisions (from review)

| # | Topic | Decision |
|---|-------|----------|
| 1 | How `my/eat-new` receives the directory | `&optional dir` parameter (Option A) |
| 2 | `grease--root-dir` nil handling | Handled inside `my/eat-new`: nil → falls back to `default-directory` |
| 3 | Where the code lives | `eat/firemacs-eat.el` (alongside existing `my/eat-new`) |
| 4 | Dispatch mechanism | Pure alist: mode → handler function |
| 5 | Inline vs. named handler | Named handler functions called via alist `funcall` |
| 6 | `C-u M-t` interactive prompt | None — no `C-u` prompt at all |
| 7 | Eat buffer naming | Unchanged — always `"N   <PID>"` regardless of origin |
| 8 | Unsaved grease changes warning | No warning — just spawn the terminal |
| 9 | Window behavior | Switch to eat buffer immediately (same as current) |
| 10 | Future mode plans | None imminent, but alist chosen for extensibility |
| Q1 | `derived-mode-p` vs exact `eq` | `derived-mode-p` — more flexible |
| Q2 | Explicit `(require 'cl-lib)` | Yes — add explicit require |
| Q3 | Handler function signature | No arguments — reads buffer-local state |
| Q4 | `defvar` vs `defcustom` | `defvar` — internal plumbing |
| Q5 | Silent vs logged nil fallback | Silent — nil is a normal edge case |
| Q6 | `featurep 'grease` guard | Yes — warn and fall through if grease not loaded |

---

## Architecture

```
M-t  →  my/eat-new-dispatch
          │
          ├─ (derived-mode-p 'grease-mode)?
          │    →  funcall my/eat-new-from-grease
          │         └─ (my/eat-new grease--root-dir)
          │
          └─ fallthrough
               └─ (my/eat-new)   ; no arg → default-directory
```

### Modified `my/eat-new`

Gains `&optional dir`. If `dir` is non-nil and exists, the shell spawns there.
If `dir` is nil or nonexistent, falls back to `default-directory`.

```elisp
(defun my/eat-new (&optional dir)
  "Spawn a new eat terminal at the lowest available index.
Buffer is named like \"1   <PID>\" (index +   + PID).

The shell starts in `default-directory', or in DIR when DIR names an
existing directory.  If DIR is a file, its parent directory is used.
If DIR is nil or does not exist, `default-directory' is used silently."
  (interactive)
  (let* ((index (my/eat-next-available))
         (shell (or explicit-shell-file-name
                    (getenv "ESHELL")
                    shell-file-name))
         (cwd (cond
               ((and dir
                     (let ((expanded (expand-file-name dir)))
                       (cond
                        ((file-directory-p expanded)
                         (file-name-as-directory expanded))
                        ((file-exists-p expanded)
                         (file-name-directory expanded))
                        (t nil)))))
               (t default-directory))))
    (let ((buf-name (format "%d   waiting" index)))
      (with-current-buffer (get-buffer-create buf-name)
        (setq default-directory cwd)
        (eat-mode)
        (pop-to-buffer-same-window (current-buffer))
        (unless (and eat-terminal
                     (eat-term-parameter eat-terminal 'eat--process))
          (eat-exec (current-buffer) (buffer-name)
                    "/usr/bin/env" nil
                    (list "sh" "-c" shell)))
        (when-let* ((proc (eat-term-parameter eat-terminal 'eat--process))
                    ((process-live-p proc)))
          (rename-buffer (format "%d   %d" index (process-id proc))))
        (current-buffer)))))
```

**Key change from current:** `let` → `let*`; `cwd` binding now checks `dir`
first (with `expand-file-name`, directory check, file→parent coercion),
falling back to `default-directory`.  Nonexistent `dir` → silent fallback
(no `user-error` — per Q2 decision: nil handling is graceful).

### Require

Add at the top of `firemacs-eat.el` (after `lexical-binding`):

```elisp
(require 'cl-lib)
```

### Dispatch alist

```elisp
(defvar my/eat-new-dispatch-alist
  '((grease-mode . my/eat-new-from-grease))
  "Alist mapping major-mode symbols to eat-spawn handler functions.
Each handler is called with no arguments and should call `my/eat-new'
with an appropriate directory (or no argument for `default-directory').
The dispatcher walks this list with `derived-mode-p', so entries match
any mode derived from the key symbol.")
```

### Grease handler

```elisp
(defun my/eat-new-from-grease ()
  "Spawn eat in the root directory of the current grease buffer.
Falls back to `default-directory' when `grease--root-dir' is nil.
If grease is not loaded, warns and falls through to `my/eat-new'."
  (if (featurep 'grease)
      (my/eat-new grease--root-dir)
    (display-warning
     'eat
     (concat "grease-mode detected but grease.el is not loaded; "
             "spawning in default-directory")
     :warning)
    (my/eat-new)))
```

### Dispatcher

```elisp
(defun my/eat-new-dispatch ()
  "Spawn a new eat terminal, mode-aware.
When the current buffer uses a mode listed in `my/eat-new-dispatch-alist',
calls the associated handler.  Otherwise falls through to `my/eat-new'
with no argument (uses `default-directory')."
  (interactive)
  (if-let ((handler (cdr (cl-assoc major-mode my/eat-new-dispatch-alist
                                   :test #'derived-mode-p))))
      (funcall handler)
    (my/eat-new)))
```

---

## Keybind change

In `keybinds.el`, replace:

```elisp
"M-t" 'my/eat-new
```

with:

```elisp
"M-t" 'my/eat-new-dispatch
```

No change to the `eat-semi-char-non-bound-keys` / `eat-semi-char-mode-map`
block — that block operates on the `"M-t"` key chord, not the command
symbol, so it keeps working transparently.

---

## Resolved open questions

### Q1. `derived-mode-p` matching in the alist  ✅

**Decision: `derived-mode-p`.** More flexible, matches any mode derived from
the key symbol (e.g., a hypothetical mode inheriting from `grease-mode`).

### Q2. `cl-assoc` dependency  ✅

**Decision: add explicit `(require 'cl-lib)`.** Don't rely on transitive
imports; make the dependency explicit at the top of `firemacs-eat.el`.

### Q3. Handler function signature  ✅

**Decision: no arguments.** Each handler reads what it needs from the
current buffer's local state. Simple, sufficient. Revisit if a future
mode needs caller context.

### Q4. Dispatch alist — `defvar` or `defcustom`  ✅

**Decision: `defvar`.** Internal plumbing, not user-facing. Users who want
to extend it can `add-to-list` in their config.

### Q5. Silent or logged fallback when `dir` is nil/nonexistent  ✅

**Decision: silent.** Nil is a normal edge case, not a bug. Logging would be
noisy for a routine fallback.

### Q6. Soft dependency check for `grease--root-dir`  ✅

**Decision: `(featurep 'grease)` guard with `display-warning` fallback.**
If `grease.el` somehow isn't loaded when M-t is pressed in a grease buffer,
the handler warns and falls through to `(my/eat-new)` instead of signaling
an unbound-variable error.

---

## Test checklist (after applying)

1. `M-t` from any non-grease buffer → identical to current behavior.
2. `M-t` from a grease buffer → spawns eat in `grease--root-dir`.
3. `M-t` from a grease buffer with `grease--root-dir = nil` → spawns in
   `default-directory` (silent fallback).
4. `(my/eat-new "/some/valid/dir")` → shell starts there.
5. `(my/eat-new nil)` → shell starts in caller's `default-directory`.
6. `(my/eat-new "/tmp/nonexistent")` → silent fallback to
   `default-directory`.
7. Index recycling still works (kill terminal N, next M-t reuses N).
8. Buffer naming unchanged (`"N   <PID>"`), even from grease.
9. Unsaved grease changes — no prompt, terminal spawns normally.
10. Window switch — eat takes over the current window (same as today).
11. `eat-semi-char-non-bound-keys` still lets M-t through to Emacs.
