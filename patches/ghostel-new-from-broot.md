# PATCH — `my/ghostel-new-from-broot`: M-t spawns a terminal at broot's current directory

Status: **implemented** (4/4 decisions answered; code applied in ghostfire.el).

Decisions:
1. Handler lives in **ghostfire.el** (with an `fboundp` guard on broot's sync
   function + `declare-function`).
2. Grease removal scope: **entry only** — the alist entry is gone, but
   `my/ghostel-new-from-grease`, `my/ghostel-kill-grease-on-spawn`, and the
   "grease → root dir" header/section comments are left dormant (not
   deleted).
3. Fallback when broot's dir is unavailable: **warn + `default-directory`**.
4. The broot session is **kept alive** after spawning (source not killed).

## Goal

When `M-t` (`my/ghostel-new-dispatch`) is pressed from inside a **broot
session** (`broot-mode`), spawn the new indexed Ghostel shell terminal rooted
at the directory broot is *currently* focused on — using the same on-demand
syncing behavior as `my/consult-ripgrep-with-jump` (i.e.
`my/broot-sync-default-directory`, the procfs read of broot's live process
cwd at the moment of the call; no pollers).

The existing **grease** dispatch handler is removed and replaced by the broot
handler.

## Current behavior (as found)

- `M-t` → `my/ghostel-new-dispatch` (keybinds.el, global `override` map).
- `my/ghostel-new-dispatch-alist` (ghostfire.el) has one entry:
  `grease-mode → my/ghostel-new-from-grease`; anything else (including
  `broot-mode`) falls through to
  `(my/ghostel-new (my/ghostel-working-dir))`.
- For a broot buffer, `my/ghostel-working-dir` never sees OSC 7 (broot isn't
  a shell) and therefore returns the buffer's `default-directory`, which is
  only fresh if `my/broot-sync-default-directory` was last called there.
  Result today: **M-t from broot starts a shell at broot's (usually stale)
  launch directory.**
- The dispatch docstring is stale (says the fallback uses
  `default-directory` with no argument, but the code passes
  `my/ghostel-working-dir`).

## Proposed change

### 1. Swap the dispatch alist entry (ghostfire.el)

```elisp
(defvar my/ghostel-new-dispatch-alist
  '((broot-mode . my/ghostel-new-from-broot))
  "Alist mapping major-mode symbols to ghostel-spawn handler functions.
Each handler is called with no arguments and should call `my/ghostel-new'
with an appropriate directory (or no argument for `default-directory').
The dispatcher uses `derived-mode-p', so entries match any mode derived
from the key symbol.")
```

### 2. New handler `my/ghostel-new-from-broot` (ghostfire.el)

Same syncing call as `my/consult-ripgrep-with-jump`:
`(or (my/broot-sync-default-directory) default-directory)` — the sync
function both refreshes the broot buffer's `default-directory` and returns
the live directory.

```elisp
(defun my/ghostel-new-from-broot ()
  "Spawn ghostel rooted at the directory broot is currently showing.
Reads broot's live working directory via `my/broot-sync-default-directory'
(the same on-demand, procfs-based sync used by
`my/consult-ripgrep-with-jump'), so the new terminal starts where broot is
rooted at the moment M-t is pressed.

If broot.el isn't loaded or the broot process directory can't be read,
warns and falls through to `my/ghostel-new' in `default-directory'."
  (if (fboundp 'my/broot-sync-default-directory)
      (my/ghostel-new (or (my/broot-sync-default-directory)
                          default-directory))
    (display-warning
     'ghostel
     (concat "broot-mode detected but broot.el is not loaded; "
             "spawning in default-directory")
     :warning)
    (my/ghostel-new)))
```

Notes:
- The handler lives in ghostfire.el (sibling of the dispatch machinery, same
  pattern as the removed grease handler, which guarded on `(featurep
  'grease)`); the dir query itself stays in broot.el. ghostfire loads before
  broot.el, so the guard is `fboundp` at run time — no load-order coupling.
- `my/broot-current-directory`/`my/broot-sync-default-directory` default to
  the *current buffer*, which is the broot session when the handler runs.

### 3. Remove the grease handler

- Delete the alist entry (done in step 1).
- Delete `my/ghostel-new-from-grease`.
- Delete `my/ghostel-kill-grease-on-spawn` (now unused).
- Update the file header feature line and the section comment that still say
  "grease → root dir, kill grease after".

### 4. Fix the stale dispatch docstring (adjacent cleanup)

`my/ghostel-new-dispatch` currently documents a no-argument fallback using
`default-directory`; make it match the code (falls through rooted at
`my/ghostel-working-dir`, i.e. live OSC 7 cwd in terminals, else
`default-directory`).

## Behavior change table

| Context | Before | After |
|---------|--------|-------|
| In a broot session, press M-t | Generic path → shell starts at broot's stale `default-directory` | Shell starts at broot's **current** directory (live sync) |
| In a Grease buffer, press M-t | Save prompt → terminal at grease root → grease buffer killed (defcustom, default t) | Generic path: no save prompt, terminal at `my/ghostel-working-dir` (= grease buffer `default-directory`); grease buffer stays alive |
| Any other buffer | Terminal at `my/ghostel-working-dir` | Unchanged |
| Dispatch docstring | Stale | Fixed |

## Validation

- Byte-compile ghostfire.el (+ broot.el unchanged) clean.
- Live QA: open broot, Enter into a deep dir, press M-t → new indexed
  terminal opens at that dir (`pwd` confirms); press M-t from a plain buffer
  and from a Grease buffer to confirm the generic path is sane.

## Open questions

1. Handler location — ghostfire.el (proposed) vs broot.el?
2. Removal scope — delete grease defun + defcustom + header/comment
   references entirely, or keep them dormant?
3. Fallback when broot's dir can't be read — warn + `default-directory`
   (proposed) vs silent + `my/ghostel-new` vs warn + `my/ghostel-working-dir`?
4. Broot session after spawn — keep it alive (proposed; unlike grease, the
   source isn't killed) vs kill it like the grease flow did?
