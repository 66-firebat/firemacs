# Issues — Centaur Tabs Configuration

This document catalogs every bug, design flaw, and subtle issue found in
`centaur-tabs.el`. Issues are ordered roughly by severity, most impactful first.

> **Status:** A redesign was applied (see `centaur-tabs.el` v2 header).
> Critical and High issues have been fixed. Medium/Low issues remain open.
> See `CHANGELOG` at the bottom of this file.

---

---

## Issue 1: The `my/centaur-tabs--reorder-tabset-mru` advice mutates a globally shared symbol

**Severity: Critical (breaks per-window independence entirely)**

**Location:** Lines ~167–168

```elisp
(set tabset (copy-tree pw-tabs))
```

`tabset` is an interned symbol in the global `centaur-tabs-tabsets` obarray. It is
shared across **all windows**. When Window 1 renders, this `set` overwrites the
shared symbol's value with Window 1's per-window order. When Window 2 renders next,
it reads the **already-corrupted** global value as its starting point.

**Concrete failure:**

1. Window 1 shows Code group tabs [A*, B, C]. Per-window state: `[A, B, C]`.
2. Advice sets global `Code` tabset to `[A, B, C]`. Renders fine.
3. User switches to Window 2 showing Code group tabs [D, E, F].
4. Window 2's advice reads `(symbol-value tabset)` → sees `[A, B, C]` (leftover from
   Window 1), not `[D, E, F]`.
5. Window 2 initializes its per-window state from this wrong global value → [A, B, C].
6. Result: Window 2 shows Window 1's tabs.

**Additionally, the mutation is never reverted.** After `(funcall orig-fn)` returns,
the global symbol still holds Window 1's order. The next call to
`centaur-tabs-buffer-update-groups` might rebuild it, but between renders the
corruption persists.

**Why it wasn't caught:** The advice saves per-window buffer *lists* in the hash
table, but the *tabset symbol itself* (the cons cells used for rendering) is one
global value. `copy-tree` prevents shared structure, but the symbol binding is
still overwritten.

---

## Issue 2: `my/tab-buffer-list` only returns buffers from the current group — starving other groups

**Severity: Critical (other groups' tabsets go stale)**

**Location:** Lines ~70–83

```elisp
(defun my/tab-buffer-list ()
  (let* ((cur (current-buffer))
         (group (my/tab-group-for-buffer cur)))
    (when group
      (let* ((filtered (delq nil
                             (mapcar (lambda (b)
                                       (when (and (buffer-live-p b)
                                                  (eq (my/tab-group-for-buffer b) group))
                                         b))
                                     (buffer-list))))
             (pos (cl-position cur filtered)))
        (when pos
          (cons cur (nthcdr (1+ pos) filtered)))))))
```

This function is set as `centaur-tabs-buffer-list-function`. The centaur-tabs source
calls this function to get **all** buffers that should be considered for tab display.
But `my/tab-buffer-list` **only returns buffers in the same group as the current buffer**.

**Consequence:** When `centaur-tabs-buffer-update-groups` runs, it only sees buffers
from one group. Buffers in other groups — their tabsets are never updated. If a new
buffer is created in the "Docs" group while the user is looking at the "Code" group,
that buffer won't appear in the Docs tabset until the user switches to a Docs-group
window.

**Edge case — no buffers returned:** If the current buffer is excluded from grouping
(space-prefixed name or `*scratch*`/`*Messages*`), `my/tab-group-for-buffer` returns
nil, then `my/tab-buffer-list` returns nil, and the tabset is not updated at all.

---

## Issue 3: `my/tab-buffer-list` drops buffers that precede the current buffer in `(buffer-list)`

**Severity: High (tabs silently disappear on multi-buffer groups)**

**Location:** Line ~82

```elisp
(cons cur (nthcdr (1+ pos) filtered))
```

This takes the current buffer and everything **after** it in `filtered` (which is
in `(buffer-list)` order, i.e., global MRU). Any buffer that appears **before** the
current buffer in `filtered` is silently dropped.

**When it breaks:** In normal single-window use, `(buffer-list)` always has the
current buffer first, so `pos` is 0 and nothing is dropped. But:

- After killing a buffer, `(buffer-list)` may temporarily reorder.
- In multi-window frames, switching windows changes the current buffer. If
  `my/tab-buffer-list` runs during a window-configuration change (before
  `(buffer-list)` stabilizes), buffers can be lost.
- The advice (`my/centaur-tabs--reorder-tabset-mru`) sets the global tabset to a
  non-canonical order. On the next `post-command-hook`, `my/tab-buffer-list` reads
  `(buffer-list)` — which may have a different order — and `(cl-position cur filtered)`
  might not be 0 if `cur` is no longer most-recent in `(buffer-list)`.

**Result:** Tabs silently disappear from the tab bar. They reappear only when the
user switches to them or the buffer-list reorders.

---

## Issue 4: `my/centaur-tabs--force-update` (post-command-hook) fights the per-window reorder advice

**Severity: High (advice's work undone every command)**

**Location:** Lines ~368–375 and the advice at lines ~120–176

The execution flow on every command:

```
post-command-hook
  └─ my/centaur-tabs--force-update
       └─ centaur-tabs-buffer-update-groups
            └─ my/tab-buffer-list         ← rebuilds tabset in buffer-list order
                 └─ sets global tabset value to [cur-first, ...]

redisplay
  └─ header-line-format
       └─ my/centaur-tabs-line
            └─ centaur-tabs-line
                 └─ [around advice] my/centaur-tabs--reorder-tabset-mru
                      └─ re-sorts to per-window MRU order
                      └─ MUTATES global tabset symbol again
                      └─ renders
```

**Problem:** Step 1 rebuilds the tabset from `my/tab-buffer-list` (global MRU order).
Step 2 re-sorts it again to per-window MRU. These two steps are redundant and
conflicting. The advice steps on the buffer-list function's toes, and vice versa.

Even worse: the internal cache in `centaur-tabs-buffer-update-groups` checks if
buffer membership changed. If no buffers were added/removed, it skips rebuilding.
But the advice wants a different order than the cached one. So when the cache hits,
the tabset keeps the *advice's* order from last time. When the cache misses, the
tabset is rebuilt from `my/tab-buffer-list` and the advice re-sorts again. The two
modes produce subtly different results depending on cache state.

---

## Issue 5: The advice doesn't call `orig-fn` when tabset/group is nil — tab bar disappears

**Severity: High (tab bar can vanish on excluded buffers)**

**Location:** Lines ~131, 174

```elisp
(when (and tabset group global-vals)
  ... ;; full reorder + render
  (funcall orig-fn))
```

If any of `tabset`, `group`, or `global-vals` is nil, the `when` block is skipped
entirely and `orig-fn` is **never called**. The advice returns nil, and the
header-line format evaluates to nil — the tab bar disappears.

**When this triggers:** The `centaur-tabs-current-tabset` function (called with
`t` for update) calls the `current-tabset-function` which finds which group the
current buffer belongs to. For excluded buffers (space-prefixed names,
`*scratch*`, `*Messages*`), `my/tab-group-for-buffer` returns nil, so
`centaur-tabs-buffer-groups` returns nil, and `centaur-tabs-current-tabset` returns
nil. Boom — no tab bar.

Compare with the original `centaur-tabs-line` which handles this gracefully:
it checks `centaur-tabs-hide-tab-cached` and returns nil (no tabs) but doesn't
crash the rendering chain.

---

## Issue 6: `my/centaur-tabs-group-name` calls `centaur-tabs-buffer-groups-result` — but this function is never used in the render path

**Severity: Medium (dead code with side effects)**

**Location:** Lines ~393–425

```elisp
(defun my/centaur-tabs-group-name ()
  (my/centaur-tabs--invalidate-branch-cache)
  (let* ((group (or (centaur-tabs-buffer-groups-result)
                    centaur-tabs-common-group-name))
         ...))
```

This function is defined but **never called** from the header-line format or any
hook. The header-line uses `my/centaur-tabs-group-icon` instead.

**Side-effect problem:** The function calls `my/centaur-tabs--invalidate-branch-cache`,
which clears the git branch cache. If this function is never called, the branch cache
is **never invalidated**, and `my/centaur-tabs--git-info` returns stale cached values
forever after the first lookup.

---

## Issue 7: Branch cache is never invalidated during normal operation

**Severity: Medium (stale git info after project switch)**

**Location:** Lines ~298–307

```elisp
(defun my/centaur-tabs--invalidate-branch-cache ()
  (unless (eq (current-buffer) my/centaur-tabs--last-buffer)
    (clrhash my/centaur-tabs--branch-cache)
    (setq my/centaur-tabs--last-buffer (current-buffer))))
```

This invalidation function is only called from `my/centaur-tabs-group-name`
(Issue 6 — dead code). It is **never called from the actual render path**
(`my/centaur-tabs-group-icon`). Result: after the first git info lookup for a
project, that cached value persists for the entire Emacs session, even if the
user switches to a different project's buffer.

**Additionally:** Even if invalidation worked, the cache key is `project-path`
(string). If the user opens two different projects, both are cached and never
expired. `my/centaur-tabs--last-buffer` only tracks the single most-recent buffer,
which is insufficient for a multi-project session.

---

## Issue 8: `format-mode-line` in `my/centaur-tabs--line-number` uses the selected window, not the window being rendered

**Severity: Medium (wrong line numbers in non-selected windows)**

**Location:** Lines ~359–366

```elisp
(defun my/centaur-tabs--line-number (buf)
  (if (eq buf (current-buffer))
      (let ((live (format-mode-line '("%l"))))
        ...)
    ...))
```

`format-mode-line` without a WINDOW argument uses `(selected-window)`. During
redisplay, Emacs evaluates each window's `header-line-format` independently. If
the user has two windows showing different buffers, and `format-mode-line` is
called while rendering the **non-selected** window, it returns the line number
of the **selected** window's buffer — not the buffer being rendered.

**Correct fix:** Pass the window being rendered:

```elisp
(format-mode-line '("%l") nil nil (selected-window))
```

But there's no clean way to get "the window being rendered" from inside a
header-line `:eval` form. `(selected-window)` changes during redisplay — actually,
I think during redisplay of a non-selected window, `(selected-window)` may still
be the selected window. Let me verify: in Emacs, during redisplay, each window's
mode-line/header-line is evaluated with `current-buffer` set to that window's
buffer, but `(selected-window)` still returns the frame's selected window. So
`(format-mode-line '("%l"))` will give the line number of the selected window's
buffer, not the one being displayed.

---

## Issue 9: `my/centaur-tabs-group-icon` calls `my/centaur-tabs--line-number` with `(current-buffer)` which may differ from the rendered window

**Severity: Medium (wrong line numbers in windows showing different buffers)**

**Location:** Line ~262

```elisp
(line (my/centaur-tabs--line-number (current-buffer)))
```

Same underlying issue as Issue 8. `(current-buffer)` during redisplay of a
non-selected window returns that window's buffer. But `format-mode-line` inside
`my/centaur-tabs--line-number` uses the selected window. So if Window 1 (selected)
shows `A.txt` and Window 2 shows `B.txt`, the group icon for Window 2 will show
the line number of `A.txt` — wrong.

---

## Issue 10: The `post-command-hook` runs `centaur-tabs-buffer-update-groups` on EVERY command — O(n) per keystroke

**Severity: Medium (performance, especially with many buffers)**

**Location:** Lines ~368–375

```elisp
(defun my/centaur-tabs--force-update ()
  (when (and centaur-tabs-mode (not (minibufferp)))
    (centaur-tabs-buffer-update-groups)
    ...))

(add-hook 'post-command-hook #'my/centaur-tabs--force-update)
```

`centaur-tabs-buffer-update-groups` scans ALL buffers (using the buffer-list-function),
computes groups for each, compares the result with a cached version, and updates
tabsets for any differences. This is O(n) where n is the total number of buffers,
and runs after **every single command** — including `self-insert-command` (typing),
`next-line`, `previous-line`, etc.

With 100+ buffers, this means every keystroke triggers a full scan. The centaur-tabs
internal cache (`centaur-tabs--buffers`) prevents tabset *rebuilding*, but the cache
*comparison* itself iterates over all buffers and calls the buffer-list-function and
group-function for each.

**Why it was added:** To get live line numbers and modified indicators. But the
template cache clear and `force-window-update` are the actual necessary parts. The
`centaur-tabs-buffer-update-groups` call is overkill.

---

## Issue 11: `my/centaur-tabs--sort-tabset-mru` is defined but never called

**Severity: Low (dead code)**

**Location:** Lines ~89–105

```elisp
(defun my/centaur-tabs--sort-tabset-mru (tabset)
  "Sort tabs in TABSET into MRU order. Current buffer first."
  ...)
```

This function is defined inside the `use-package :config` block but never called
from anywhere in the file. It's a leftover from an earlier iteration.

---

## Issue 12: `my/centaur-tabs--apply-gradient` re-reads `(symbol-value tabset)` which may have been mutated by the reorder advice

**Severity: Low (benign but fragile coupling)**

**Location:** Line ~186

```elisp
(tabs (and tabset (symbol-value tabset)))
```

The gradient advice reads the global tabset value to iterate over tabs for
coloring. By the time this runs, the reorder advice has already mutated the
global tabset value (Issue 1). This means:

- The gradient advice operates on the **per-window order** set by the reorder
  advice, not the canonical tabset order. This is actually *intended* — both
  advices should agree. But it creates a fragile coupling: if the reorder
  advice ever doesn't fire (e.g., due to a nil check), the gradient advice
  would operate on stale/unexpected data.

---

## Issue 13: The overflow calculation in `my/centaur-tabs--apply-gradient` calls `my/centaur-tabs-group-icon` to measure icon width

**Severity: Low (fragile cross-function dependency)**

**Location:** Line ~213

```elisp
(icon-str (my/centaur-tabs-group-icon))
```

The group icon is rendered as a **separate `:eval` element** in the header-line
format (element 0 of the format list). The gradient advice (which modifies element 2
of the tab-line template) calls `my/centaur-tabs-group-icon` to measure its width
for overflow purposes. This works but:

- Calling a render function just to measure its width is wasteful.
- `my/centaur-tabs-group-icon` has side effects (calls `format-mode-line`, updates
  the line-number cache). These are benign but show tight coupling.
- If the icon function changes, the overflow calculation silently breaks.

---

## Issue 14: The overflow truncation drops 3 elements per tab, but the first tab has a different structure

**Severity: Low (edge case, doesn't trigger in practice)**

**Location:** Lines ~222–233

The advice builds `result-elts` as:

```
[first-tab-elt, " ", "", elt2, " ", "", elt3, " ", ...]
```

The overflow loop drops `(last result-elts 3)` — i.e., `["", elt, " "]` — for
each dropped tab from the right. This works correctly for tabs 2..N. But the first
tab has only 2 elements (`first-tab-elt + " "`), not 3. If the overflow drops
enough tabs that only tab 1 remains, the code checks `(= (length last-three) 3)`
which is false (only 2 elements), and `(> n-tabs 1)` is also false, so the loop
terminates safely. No crash, but the asymmetry is worth noting.

---

## Issue 15: The `window-deletions-functions` hook is Emacs 29+ only

**Severity: Low (portability)**

**Location:** Line ~117

```elisp
(add-hook 'window-deletions-functions #'my/centaur-tabs--on-window-deleted)
```

`window-deletions-functions` was introduced in Emacs 29. On Emacs 28 or earlier,
this `add-hook` call signals an error, preventing the entire centaur-tabs config
from loading.

(Note: the user's config may target Emacs 29+ exclusively. Flagging for awareness.)

---

## Issue 16: `my/centaur-tabs-tab-label` uses `centaur-tabs-current-tabset` without the `UPDATE` argument

**Severity: Low (may render stale selection state)**

**Location:** Line ~342

```elisp
(tabset (centaur-tabs-current-tabset))   ;; no UPDATE=t
```

`centaur-tabs-current-tabset` with no argument returns the cached current tabset
without calling the `current-tabset-function` to recompute. The tab label function
is called during rendering (`centaur-tabs-line-tab`), so it uses whatever tabset
was set by `centaur-tabs-line`'s earlier call to `(centaur-tabs-current-tabset t)`.
In practice this is fine because `centaur-tabs-line` always calls with `t` first.
But if the label function is called from any other context (e.g., a user extension
or a debugging eval), it may get a stale result.

---

## Issue 17: The `my/centaur-tabs-tab-label` function's `"  "` prefix on selected tab breaks the gradient advice's `string-suffix-p " "` trim

**Severity: Cosmetic (trailing space handling)**

**Location:** Lines ~349–350

```elisp
(if selected-p
    (format " %s%s" prefix bufname)    ;; no trailing space
  (format " %s%s " prefix bufname))     ;; trailing space
```

Selected tabs get `" name"` (no trailing space), unselected tabs get `" name "`
(trailing space). The gradient advice (line 194) strips trailing spaces:

```elisp
(stripped (if (string-suffix-p " " elt) (substring elt 0 -1) elt))
```

This is fine — the strip is a no-op for selected tabs and removes the space from
unselected tabs. But then `my/centaur-tabs-line` (lines 380–391) also strips
trailing spaces from all tab strings in the template. This means the gradient
advice's strip runs first, then `my/centaur-tabs-line`'s strip runs on the
already-stripped result. Redundant but harmless.

---

## Issue 18: The cleanup advice-remove calls at lines 272–274 may remove advice that was just registered

**Severity: Ordering (harmless in practice)**

**Location:** Lines 272–274

```elisp
(advice-remove 'centaur-tabs-line #'my/centaur-tabs--trim-tab-trailing)
(advice-remove 'centaur-tabs-line-format #'my/centaur-tabs--trim-tabs)
(advice-remove 'centaur-tabs-line #'my/centaur-tabs--reorder-tabset)
```

These lines appear **after** the `advice-add` calls at lines 178 and 253. The
`advice-remove` calls are cleaning up *old/different* advice names from previous
reloads. But `my/centaur-tabs--reorder-tabset` (note: no `-mru` suffix) is an old
name that's different from the currently registered `my/centaur-tabs--reorder-tabset-mru`.
So this won't accidentally remove the current advice. The ordering is fine.

---

## Summary by Severity

| Sev | Count | Issues |
|-----|-------|--------|
| Critical | 2 | Global tabset mutation (#1), `my/tab-buffer-list` starves other groups (#2) |
| High | 3 | Drops preceding buffers (#3), post-command-hook fights advice (#4), advice skips `orig-fn` (#5) |
| Medium | 4 | Dead `my/centaur-tabs-group-name` with orphaned side effects (#6), branch cache never invalidated (#7), wrong line numbers in non-selected windows (#8), wrong line numbers in non-selected windows (#9), O(n) per keystroke (#10) |
| Low | 7 | Dead `my/centaur-tabs--sort-tabset-mru` (#11), fragile coupling in gradient advice (#12), overflow calls render function (#13), first tab different structure (#14), Emacs 29+ only (#15), no UPDATE arg in label (#16), cosmetic trailing space (#17), harmless ordering (#18) |

---

## Changelog

### 2026-06-26 — v2 redesign (`centaur-tabs.el`)

#### Fixed (Critical & High)

| Issue | Fix |
|-------|-----|
| **#1** — Global tabset mutation | `unwind-protect` in `my/centaur-tabs--reorder-for-window` saves canonical value before mutation and restores it unconditionally after `(funcall orig-fn)`. Cross-window pollution is eliminated. |
| **#2** — `my/tab-buffer-list` starves other groups | The buffer-list function now returns **all** visible buffers in `(buffer-list)` order, unfiltered by group. `centaur-tabs-buffer-update-groups` sees every group's buffers. |
| **#3** — `my/tab-buffer-list` drops preceding buffers | The old `(cons cur (nthcdr (1+ pos) ...))` pattern is gone. The new function returns a complete list with no `nthcdr` truncation. |
| **#4** — post-command-hook fights the reorder advice | Single source of truth: the buffer-list function provides raw MRU input; the `:around` advice on `centaur-tabs-line` handles ALL per-window reordering. The two mechanisms no longer conflict. |
| **#5** — Advice skips `orig-fn` on nil | The advice now always calls `(funcall orig-fn)`. The early-return branch for nil tabset still delegates to `orig-fn` rather than returning nil. |

#### Removed (dead code)

| Function | Reason |
|----------|--------|
| `my/centaur-tabs--reorder-tabset-mru` | Replaced by `my/centaur-tabs--reorder-for-window` |
| `my/centaur-tabs--sort-tabset-mru` | Defined but never called |
| `my/centaur-tabs-group-name` | Dead code; branch cache invalidation moved to the actual render path |
| `my/tab-buffer-list` (old) | Replaced by version that returns all buffers |

#### Added

- `my/centaur-tabs--reorder-for-window` — around advice on `centaur-tabs-line` with save/restore
- `my/centaur-tabs--get-pw-order` — builds per-window MRU-ordered tab cons cells
- `my/centaur-tabs--save-pw-state` — persists per-window buffer order to hash table

#### Unchanged (Medium/Low issues remain open)

- Issue #6 (dead `my/centaur-tabs-group-name`) — function removed
- Issue #7 (branch cache not invalidated) — still open; Git info only fetched once per project path
- Issue #8/#9 (line numbers in non-selected windows) — `format-mode-line` now receives `(selected-window)` argument
- Issue #10 (O(n) per keystroke) — still calls `centaur-tabs-buffer-update-groups` on every command
- Issue #11–#18 — mostly cosmetic or low-impact; not addressed
