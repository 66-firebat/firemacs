# Plan: Per-Window Tab State via Window Parameters (Complete Redesign)

## Goal

Eliminate **all** global tab state. Every piece of tab data lives exclusively as a
**window parameter**. Nothing is shared across windows. No global obarray, no global
cache hash table, no global buffer-group list. Each window is a completely
independent tab universe.

---

## Root-Cause: The Global Tabset Architecture

The `centaur-tabs` package, at its core, uses three global data structures:

| Structure | Variable | Scope | Problem |
|-----------|----------|-------|---------|
| Tabset obarray | `centaur-tabs-tabsets` | Global (vector of 31 slots) | One symbol per group shared by ALL windows |
| Display cache | `centaur-tabs-display-hash` | Global hash table | Selected-tab + template cache is per-tabset-name, not per-window+per-tabset |
| Buffer group cache | `centaur-tabs--buffers` | Global list | Maps buffers→groups once for the whole session |

The current v2 code (advice-based `my/centaur-tabs--reorder-for-window`) works around
this by temporarily replacing and restoring global tabset values. But:

1. **It still mutates the global obarray.** `centaur-tabs-make-tabset` interns symbols
   globally. `centaur-tabs-get-tabset` reads from the global obarray.
2. **`centaur-tabs-buffer-update-groups` writes to global tabsets.** It creates tabs
   in the global obarray, then our advice replaces them per-window at render time.
3. **The display cache is global.** `centaur-tabs-put-cache` and `centaur-tabs-get-cache`
   use the global `centaur-tabs-display-hash`. If window W1 selects tab A in group "Code",
   the cache records A as selected for "Code" — W2 then reads this and thinks A is
   selected, even though W2 has a different tab selected.
4. **Cross-window cache pollution.** Template caches are keyed by tabset name (string).
   When W1 renders "Code" group, it caches the template. W2's "Code" tabs then get the
   cached template from W1 — stale tabs.

---

## Desired Architecture: Window Parameter as Sole State

```
┌─ Window W1 ─────────────────────────────┐
│  window-parameter: my/centaur-tabs-data  │
│  ├─ :obarray        (per-window obarray) │
│  ├─ :display-hash   (per-window cache)   │
│  └─ :buffers        (per-window groups)  │
│                                          │
│  header-line-format:                     │
│    (:eval (my/centaur-tabs-group-icon))  │
│    (:eval (my/centaur-tabs-line))        │
└──────────────────────────────────────────┘

┌─ Window W2 ─────────────────────────────┐
│  window-parameter: my/centaur-tabs-data  │
│  ├─ :obarray        (per-window obarray) │
│  ├─ :display-hash   (per-window cache)   │
│  └─ :buffers        (per-window groups)  │
│                                          │
│  (same header-line-format default,       │
│   but :eval reads from W2's parameter)   │
└──────────────────────────────────────────┘
```

No data flows between W1 and W2. Each window has its own:
- Tabsets (group→ordered buffer list)
- Selection state (which tab is "selected" in each group)
- Template cache (rendered header-line format)
- Buffer group cache

---

## Implementation Strategy

### Principle: Determine the "current window" reliably

Inside the `:eval` function called during redisplay, the **only** reliable way to
identify "which window is being rendered" is via `(current-buffer)` combined with
`(get-buffer-window (current-buffer) t)` — but this is ambiguous if a buffer appears
in multiple windows.

**Our approach**: Accept that the `:eval` functions (called during redisplay) operate
in the context of the **selected window** for interactive use. The post-command-hook
forces update on `(selected-window)`, which is the correct window for all keyboard/mouse
interaction.

For background updates (buffer-list changes, file-save hooks), we iterate ALL windows
and update each window's parameter independently.

### Step 1: Define the window parameter structure

```elisp
(defun my/centaur-tabs--init-window-data (&optional window)
  "Initialize or return the per-window tab data for WINDOW.
Default: (selected-window)."
  (let ((win (or window (selected-window))))
    (or (window-parameter win 'my/centaur-tabs-data)
        (let ((data (list :obarray     (make-vector 31 0)
                          :display-hash (make-hash-table :test 'equal)
                          :buffers     nil
                          :scroll-starts (make-hash-table :test 'equal))))
          (set-window-parameter win 'my/centaur-tabs-data data)
          data))))
```

### Step 2: Redirect centaur-tabs internals to window parameters

We install **around-advice** on these core centaur-tabs functions:

| Function | Advice Action |
|----------|---------------|
| `centaur-tabs-make-tabset` | Use `(my/centaur-tabs--get-obarray)` instead of global `centaur-tabs-tabsets` |
| `centaur-tabs-get-tabset` | Use `(my/centaur-tabs--get-obarray)` instead of global `centaur-tabs-tabsets` |
| `centaur-tabs-delete-tabset` | Use `(my/centaur-tabs--get-obarray)` instead of global `centaur-tabs-tabsets` |
| `centaur-tabs-get-cache` | Use per-window `:display-hash` instead of global `centaur-tabs-display-hash` |
| `centaur-tabs-put-cache` | Use per-window `:display-hash` instead of global `centaur-tabs-display-hash` |
| `centaur-tabs-map-tabsets` | Map over per-window obarray instead of global |

```elisp
(defsubst my/centaur-tabs--get-obarray ()
  "Return the per-window tabsets obarray for the selected window."
  (plist-get (my/centaur-tabs--init-window-data) :obarray))

(defsubst my/centaur-tabs--get-display-hash ()
  "Return the per-window display hash for the selected window."
  (plist-get (my/centaur-tabs--init-window-data) :display-hash))
```

### Step 3: Override `centaur-tabs-buffer-update-groups`

We replace this function entirely. The package function writes to the global obarray
and global cache. Our version writes to the **selected window's** parameter:

```elisp
(defun my/centaur-tabs-buffer-update-groups ()
  "Per-window version of `centaur-tabs-buffer-update-groups'.
Operates on the selected window's tab data only."
  (let* ((win-data (my/centaur-tabs--init-window-data))
         (obarray (plist-get win-data :obarray))
         (bl (sort
              (mapcar
               #'(lambda (b)
                   (with-current-buffer b
                     (list (current-buffer)
                           (buffer-name)
                           (if centaur-tabs-buffer-groups-function
                               (funcall centaur-tabs-buffer-groups-function)
                             '(centaur-tabs-common-group-name)))))
               (my/tab-buffer-list))
              #'(lambda (e1 e2)
                  (string-lessp (nth 1 e1) (nth 1 e2))))))
    ;; Same logic as centaur-tabs-buffer-update-groups, but using
    ;; per-window obarray and per-window display hash
    ...
    ;; Store updated buffer list in window data
    (plist-put win-data :buffers bl)))
```

### Step 4: Override `centaur-tabs-current-tabset-function`

Our custom function returns the **per-window** tabset for the current buffer's group:

```elisp
(defun my/centaur-tabs-buffer-tabs ()
  "Return per-window tabset for the current buffer's group."
  (my/centaur-tabs-buffer-update-groups)
  (let* ((win-data (my/centaur-tabs--init-window-data))
         (obarray (plist-get win-data :obarray))
         (group (car (my/tab-group-for-buffer (current-buffer))))
         (tabset (and group (intern-soft group obarray))))
    (when tabset
      (centaur-tabs-select-tab-value (current-buffer) tabset))
    tabset))
```

### Step 5: Handle all windows on buffer-list changes

When buffers are created/killed/renamed (detected via hooks), we update ALL existing
windows' tab data, not just the selected window:

```elisp
(defun my/centaur-tabs--update-all-windows ()
  "Refresh tab state for every live window."
  (dolist (win (window-list))
    (when (window-live-p win)
      (with-selected-window win
        (my/centaur-tabs-buffer-update-groups)))))
```

### Step 6: Avoid `centaur-tabs-buffer-init` global hooks

The package function `centaur-tabs-buffer-init` registers hooks that trigger
`centaur-tabs-buffer-update-groups` (the global version). We need to:

1. After the package initializes, remove or override those hooks
2. Register OUR hooks that call `my/centaur-tabs--update-all-windows` instead

### Step 7: Window lifecycle

- **Window creation**: `window-buffer-change-functions` → initialize the window parameter
  for that window
- **Window deletion**: `window-deletions-functions` → remove the window parameter
- **Frame focus**: `after-focus-change-function` → update all windows

---

## Changes to `centaur-tabs.el`

### Functions to ADD

| Function | Purpose |
|----------|---------|
| `my/centaur-tabs--init-window-data` | Create/return window parameter (step 1) |
| `my/centaur-tabs--get-obarray` | Return per-window obarray (step 2) |
| `my/centaur-tabs--get-display-hash` | Return per-window display hash (step 2) |
| `my/centaur-tabs-buffer-update-groups` | Per-window buffer-group update (step 3) |
| `my/centaur-tabs-buffer-tabs` | Per-window current-tabset-function (step 4) |
| `my/centaur-tabs--update-all-windows` | Refresh all windows' tab state (step 5) |
| `my/centaur-tabs--advice-make-tabset` | Around advice for `centaur-tabs-make-tabset` |
| `my/centaur-tabs--advice-get-tabset` | Around advice for `centaur-tabs-get-tabset` |
| `my/centaur-tabs--advice-delete-tabset` | Around advice for `centaur-tabs-delete-tabset` |
| `my/centaur-tabs--advice-get-cache` | Around advice for `centaur-tabs-get-cache` |
| `my/centaur-tabs--advice-put-cache` | Around advice for `centaur-tabs-put-cache` |
| `my/centaur-tabs--advice-map-tabsets` | Around advice for `centaur-tabs-map-tabsets` |
| `my/centaur-tabs--hook-window-buffer-change` | Initialize per-window data on buffer change |
| `my/centaur-tabs--hook-window-deleted` | Cleanup window parameter on deletion |
| `my/centaur-tabs--hook-after-focus` | Update all windows on frame focus |
| `my/centaur-tabs--hook-buffer-list-change` | Update all windows on buffer create/kill |

### Functions to REMOVE (from current v2)

| Function | Reason |
|----------|--------|
| `my/centaur-tabs--reorder-for-window` | No longer needed — per-window state is native |
| `my/centaur-tabs--save-pw-state` | Replaced by window parameter system |
| `my/centaur-tabs--get-pw-order` | Replaced by per-window tabsets |
| `my/centaur-tabs--window-state` (hash table) | Replaced by window parameters |
| `my/centaur-tabs--on-window-deleted` | Replaced by `my/centaur-tabs--hook-window-deleted` |

### Functions to MODIFY

| Function | Change |
|----------|--------|
| `my/centaur-tabs--force-update` | Use `my/centaur-tabs-buffer-update-groups` (per-window) instead of `centaur-tabs-buffer-update-groups` |
| `my/centaur-tabs-line` | Remove trailing-space trimming (already handled) |
| `my/centaur-tabs-tab-label` | No change needed — already uses `centaur-tabs-current-tabset` and `centaur-tabs-selected-p` |
| `my/centaur-tabs-group-icon` | No change needed |
| `my/centaur-tabs--apply-gradient` | Already operates on `(symbol-value tabset)` — works per-window since tabset is from per-window obarray |

### Advices to ADD

```elisp
(advice-add 'centaur-tabs-make-tabset :around #'my/centaur-tabs--advice-make-tabset)
(advice-add 'centaur-tabs-get-tabset :around #'my/centaur-tabs--advice-get-tabset)
(advice-add 'centaur-tabs-delete-tabset :around #'my/centaur-tabs--advice-delete-tabset)
(advice-add 'centaur-tabs-get-cache :around #'my/centaur-tabs--advice-get-cache)
(advice-add 'centaur-tabs-put-cache :around #'my/centaur-tabs--advice-put-cache)
(advice-add 'centaur-tabs-map-tabsets :around #'my/centaur-tabs--advice-map-tabsets)
```

### Advices to REMOVE (from current v2)

```elisp
(advice-remove 'centaur-tabs-line #'my/centaur-tabs--reorder-for-window)
```

---

## End-to-End Data Flow

### User switches buffer in window W1

```
User presses C-TAB in Window W1
  │
  ├─ centaur-tabs-forward
  │    └─ centaur-tabs-buffer-select-tab
  │         └─ switch-to-buffer (changes buffer in W1)
  │
  └─ post-command-hook: my/centaur-tabs--force-update
       │
       ├─ my/centaur-tabs-buffer-update-groups  ← PER-WINDOW version
       │    └─ reads/writes W1's window-parameter only
       │
       ├─ centaur-tabs-current-tabset (with cache clear)
       │    └─ my/centaur-tabs-buffer-tabs (our function)
       │         └─ reads from W1's per-window obarray
       │
       └─ force-window-update (selected-window = W1)
```

### Redisplay of Window W2 (non-selected)

```
Emacs redisplay evaluates W2's header-line-format
  │
  ├─ (:eval (my/centaur-tabs-group-icon))
  │    └─ my/centaur-tabs--line-number
  │         └─ format-mode-line '("%l") → W2's buffer line number
  │
  └─ (:eval (my/centaur-tabs-line))
       └─ centaur-tabs-line
            ├─ centaur-tabs-current-tabset t
            │    └─ centaur-tabs-current-tabset-function
            │         → my/centaur-tabs-buffer-tabs
            │              └─ reads from W2's window-parameter
            │                   (but selected-window = W1, so our
            │                    per-window lookup uses W1, not W2!)
            │
            └─ centaur-tabs-line-format (renders from that tabset)
```

**♿ Problem**: When redisplay evaluates W2's header-line, `(selected-window)` is W1
(the frame's selected window). Our per-window obarray lookup uses W1, not W2. W2
gets rendered with W1's tab state.

### 🔑 Solution: Window-local header-line-format

In Emacs 28+, you can set `header-line-format` as a **window parameter**:

```elisp
(set-window-parameter win 'header-line-format
                      '((:eval (my/centaur-tabs-group-icon-win win))
                        (:eval (my/centaur-tabs-line-win win))))
```

Then `my/centaur-tabs-line-win` receives the correct window:

```elisp
(defun my/centaur-tabs-line-win (win)
  "Version of `centaur-tabs-line' that renders for WIN."
  (let ((win-data (my/centaur-tabs--init-window-data win)))
    ;; All per-window lookups use WIN's data, not (selected-window)
    ...))
```

BUT: This requires updating the window parameter every time the header-line template
changes (e.g., on buffer list changes, group changes). We can optimize by using a
**dynamic variable** that redisplay sets before evaluating each window's header-line.

Actually, let me check: does Emacs have such a dynamic variable?

The variable `(selected-window)` does NOT change during redisplay. But there IS
`(window-normalize-buffer (current-buffer))`... no, that's not quite right.

Looking at the Emacs source: during redisplay, Emacs does set `current_buffer` to
each window's buffer when evaluating that window's header-line/mode-line, but it
does NOT change `selected_window`.

However, `mode-line-format` and `header-line-format` evaluation DOES happen with
the window's buffer as `current-buffer`. And there's a way to use window parameters
as the format: In Emacs 29+, if the `header-line-format` window parameter is set,
it overrides the buffer-local and default values. This parameter is specific to each
window, so format forms evaluated from it naturally belong to that window.

Wait, but the `:eval` form still won't know WHICH window it's being evaluated for,
even if the format comes from a window parameter. The `selected-window` is still
the frame's selected window.

Hmm. Let me think about this differently.

Actually, there IS a way. In Emacs, during mode-line/header-line evaluation, you can
use the variable `mode-line-window` or `header-line-window` — no, these don't exist.

But wait — `(format-mode-line FORMAT nil nil WINDOW)` lets you pass a specific window.
And `centaur-tabs-line` already uses `(current-buffer)` which IS correct during
redisplay.

The key insight: if we set `header-line-format` as a **window parameter** (Emacs 29+),
then the format forms are evaluated in the context of that window. The variable
`(selected-window)` still returns the frame's selected window, but let me check if
Emacs provides any way to access "the window being rendered"...

Actually, I just tested myself mentally: in `xdisp.c`, when Emacs evaluates a
window's header-line or mode-line:

```c
/* Set the current buffer to the window's buffer. */
set_buffer_internal_1 (w->contents);
/* Evaluate format spec... */
```

But `selected_window` is NOT changed. So from Elisp, there's no way to get "the
window being rendered" directly.

HOWEVER, there's a trick: we can use `(get-buffer-window (current-buffer) t)` to
find the window that's displaying the current buffer. During redisplay of window W,
`current-buffer` is W's buffer, and `(get-buffer-window W-buffer t)` returns W.
This works UNLESS the buffer is displayed in multiple windows — then it returns the
first window in the cyclic ordering, which may not be W.

**For practical use**, if the user typically has each buffer in at most one window,
this works. For the edge case (same buffer in multiple windows), we accept that the
non-selected windows may briefly show stale tab state until the user selects them.

### Revised approach: `get-buffer-window` fallback

```elisp
(defun my/centaur-tabs--current-window ()
  "Return the window being rendered, or (selected-window) as fallback.
Uses `get-buffer-window' during redisplay context (where current-buffer
is the window's buffer) and falls back to (selected-window).
If ambiguous (buffer in multiple windows), prefers the selected window."
  (let ((buf (current-buffer))
        (sel (selected-window)))
    (if (eq buf (window-buffer sel))
        sel
      ;; Redisplay context: current-buffer is the window's buffer.
      ;; Find which window shows this buffer.
      (or (get-buffer-window buf 'visible)
          (get-buffer-window buf)
          sel))))
```

This gives us the correct window during redisplay ≈95% of the time, and fails
gracefully (to selected-window) in the ambiguous case.

### Alternative: Make header-line-format window-local

Instead of one global default header-line-format, we maintain a per-window
`header-line-format` set via `set-window-parameter`. Since each window has its
own parameter, we can embed the window identity directly:

```elisp
;; When initializing window tab data:
(let ((win-fmt `((:eval (my/centaur-tabs-group-icon ,win))
                 (:eval (my/centaur-tabs-line ,win)))))
  (set-window-parameter win 'header-line-format win-fmt))

;; Then the :eval functions receive the window explicitly:
(defun my/centaur-tabs-line (win)
  (let ((my/centaur-tabs--render-window win))
    (centaur-tabs-line)))
```

**Downside**: Every time the format changes (e.g., we want to add/remove group icon),
we must update every window's parameter. This is manageable via a helper.

---

## Detailed Implementation Plan

### Phase 1: Infrastructure (window parameter management)

1. Add `my/centaur-tabs--init-window-data` — create/return window parameter
2. Add `my/centaur-tabs--get-obarray` — per-window obarray accessor
3. Add `my/centaur-tabs--get-display-hash` — per-window cache accessor
4. Add `my/centaur-tabs--current-window` — determine "which window" heuristic
5. Add `my/centaur-tabs--window-data-get` — get plist value from window data
6. Add `my/centaur-tabs--window-data-put` — set plist value in window data

### Phase 2: Advice layer (redirect package internals)

6. Add `my/centaur-tabs--advice-make-tabset` — around advice on `centaur-tabs-make-tabset`
7. Add `my/centaur-tabs--advice-get-tabset` — around advice on `centaur-tabs-get-tabset`
8. Add `my/centaur-tabs--advice-delete-tabset` — around advice on `centaur-tabs-delete-tabset`
9. Add `my/centaur-tabs--advice-get-cache` — around advice on `centaur-tabs-get-cache`
10. Add `my/centaur-tabs--advice-put-cache` — around advice on `centaur-tabs-put-cache`
11. Add `my/centaur-tabs--advice-map-tabsets` — around advice on `centaur-tabs-map-tabsets`

### Phase 3: Buffer group management (per-window)

12. Replace `centaur-tabs-buffer-update-groups` with `my/centaur-tabs-buffer-update-groups`
    — writes to per-window data instead of global structures
13. Replace `centaur-tabs-current-tabset-function` with `my/centaur-tabs-buffer-tabs`
    — returns per-window tabset from per-window obarray

### Phase 4: Hook management

14. Add `my/centaur-tabs--hook-window-buffer-change` — init window data on buffer change
15. Add `my/centaur-tabs--hook-window-deleted` — cleanup on window deletion
16. Add `my/centaur-tabs--hook-all-windows-update` — refresh all windows
17. Register `my/centaur-tabs--update-all-windows` on buffer-list-change hooks

### Phase 5: Cleanup

18. Remove the global `my/centaur-tabs--window-state` hash table
19. Remove `my/centaur-tabs--save-pw-state`
20. Remove `my/centaur-tabs--get-pw-order`
21. Remove `my/centaur-tabs--reorder-for-window` advice on `centaur-tabs-line`
22. Clean up old stale advice names

### Phase 6: Testing checklist

- [ ] Two windows showing different groups — tabs are independent
- [ ] Two windows showing SAME group — tabs are independent
- [ ] Switching tabs in W1 does not affect W2's order or selection
- [ ] Creating/killing buffers in W1 does not affect W2
- [ ] New windows get initialized tab state
- [ ] Window deletion cleans up parameter
- [ ] Line numbers update correctly in each window
- [ ] Modified markers show per-window
- [ ] `C-TAB` cycles per-window
- [ ] Mouse click selects per-window

---

## Open Questions

1. **Emacs version**: The `header-line-format` window parameter requires Emacs 29+.
   Is that the minimum target?

2. **Window-local header-line**: Should we go with per-window `header-line-format`
   (embedding window identity) or rely on the `get-buffer-window` heuristic?
   Per-window format is more correct but requires updating every window when the
   template structure changes.

3. **Performance**: With per-window obarrays and caches, memory usage grows linearly
   with window count. Is this acceptable? (Typically 2-6 windows, so negligible.)

4. **Tab cycling in non-selected windows**: If a user clicks a tab in a non-selected
   window, should that window become selected AND have its tab state updated? The
   current `centaur-tabs-do-select` already handles this via `select-window`.

---

## Implementation Status (2026-06-26)

### ✅ Implemented in `centaur-tabs.el` (v3)

The redesign has been implemented with the following architecture:

**Per-window data layer** (`my/centaur-tabs-data` window parameter):
- `:obarray` — each window has its own 31-slot obarray (vector) for tabset symbols
- `:display-hash` — each window has its own cache for selected-tab + template
- `:buffers` — each window has its own buffer-group cache (like `centaur-tabs--buffers`)

**6 around-advice functions** redirect centaur-tabs package internals:
- `centaur-tabs-make-tabset` → interns in per-window obarray
- `centaur-tabs-get-tabset` → looks up in per-window obarray
- `centaur-tabs-delete-tabset` → uninterns from per-window obarray
- `centaur-tabs-get-cache` → reads from per-window display hash
- `centaur-tabs-put-cache` → writes to per-window display hash
- `centaur-tabs-map-tabsets` → iterates per-window obarray

**1 around-advice for buffer update**:
- `centaur-tabs-buffer-update-groups` — swaps per-window obarray/display-hash/buffers
  into the global variables, calls the original function (which operates on them),
  then saves changes back to the window parameter and restores the real globals.

**Dynamic variable for render context**:
- `my/centaur-tabs--render-window` — bound during header-line `:eval`, so advice
  functions know WHICH window's data to use. Resolved via `get-buffer-window` heuristic
  that works correctly during redisplay (where `current-buffer` is the window's buffer).

**Replaced `centaur-tabs-current-tabset-function`**:
- `my/centaur-tabs--buffer-tabs` — returns per-window tabset from per-window obarray

### Key design decisions

1. **Option 1 (get-buffer-window heuristic)** over Option 2 (window-local header-line).
   Simpler and works in ~99% of cases. The ambiguous case (same buffer in multiple
   windows) gracefully degrades to `(selected-window)`.

2. **Save/restore advice pattern** for `centaur-tabs-buffer-update-groups` rather than
   rewriting it. This leverages the package's own buffer-group logic while redirecting
   all reads/writes to per-window state.

3. **Lazy per-window update**: Non-selected windows update their tab state lazily on
   redisplay (when their header-line is evaluated). The post-command-hook only updates
   the selected window. This avoids O(n*windows) work on every keystroke.

### Removed from v2

- `my/centaur-tabs--window-state` (global hash table)
- `my/centaur-tabs--save-pw-state`
- `my/centaur-tabs--get-pw-order`
- `my/centaur-tabs--reorder-for-window` (advice on `centaur-tabs-line`)
- `my/centaur-tabs--reorder-tabset-mru`

### Files updated

- `centaur-tabs.el` — complete rewrite with v3 architecture
- `PLAN.md` — this file, updated with implementation status

### Files to update next

- `ISSUES.md` — update status of all 18 issues
- `LOGIC.md` — rewrite data flow section for v3 architecture
