# Centaur Tabs — Complete Logic Guide (v4, Scratch-Built)

## Architecture Overview

This is a **completely self-built tab line system**. It does NOT use any
centaur-tabs package internals (`centaur-tabs-line`, `centaur-tabs-line-format`,
`centaur-tabs-buffer-update-groups`, `centaur-tabs-make-tabset`, etc.).

The system uses:
- **Window parameters** for all per-window state
- **Dynamic variable** for render-window resolution during redisplay
- **header-line-format** with two `:eval` forms: one for the group icon, one for
  the tab bar
- **Post-command-hook** for live updates (MRU reordering, selection tracking)
- **Minor-mode keymap** (`centaur-tabs-mode-map`) for C-TAB cycling

---

## 1. Data Model — The Window Parameter

Every window has a parameter called `my/centaur-tabs-data`. It's a plist:

```elisp
(:groups    alist      ; (group-name . (buffer buffer ...)) — all live buffers
 :selected  alist      ; (group-name . buffer) — selected buffer per group
 :mru       alist      ; (group-name . (buffer buffer ...)) — MRU-ordered list
 :scroll    alist      ; (group-name . integer) — scroll offset (unused))
```

### 1.1 Groups alist

Format: `(("Code" buf1 buf2) ("Buffers" buf3) ...)`

Each entry maps a group name (string, e.g. "Code", "Tools", "Buffers") to a list
of live buffer objects belonging to that group. The order is the order in which
buffers were first seen (global `buffer-list` order on first sync).

Maintained by `my/ct--update-window`. Synced from `my/ct--visible-buffers`.

### 1.2 Selected alist

Format: `(("Code" . buf1) ("Buffers" . buf3) ...)`

Each entry maps a group name to the currently selected buffer for that window.
Initialized to the first buffer in each group. Updated when the user switches to
a different buffer (by `my/ct--force-update`).

### 1.3 MRU alist

Format: `(("Tools" buf3 buf1 buf2) ("Code" buf4 buf5) ...)`

Each entry maps a group name to a buffer list in Most Recently Used order. The
first buffer is the most recently used. When the user switches to buffer X:
1. X is removed from its current position in the MRU list
2. X is prepended to the front (position 0)
3. The previously-first buffer shifts to position 1

Maintained by `my/ct--force-update` (post-command-hook).

---

## 2. Buffer Grouping

### 2.1 Visible Buffers — `my/ct--visible-buffers`

Returns all live buffers EXCEPT:
- Buffers whose name starts with a space
- `*scratch*` and `*Messages*`

Uses `(buffer-list)` order (Emacs global MRU).

### 2.2 Group Assignment — `my/tab-group-for-buffer`

Each buffer is assigned to exactly one group. The groups are defined in
`my/tab-group-categories`:

```elisp
'(("Code"    ""   emacs-lisp-mode lisp-mode python-mode ...)
  ("Docs"    ""   org-mode markdown-mode text-mode)
  ("Config"  ""   conf-mode)
  ("Tools"   ""   dired-mode magit-mode eat-mode vterm-mode ...)
  ("Buffers" ""))   ;; catch-all
```

The function checks the buffer's `major-mode` against each category's mode list.
The first match wins. If no mode matches, the buffer falls into "Buffers" (the
catch-all).

Returns a **list** containing the group name (a single-element list), e.g.
`("Code")` or `("Tools")`. This matches the interface that
`centaur-tabs-buffer-update-groups` expects, though we no longer call that
function.

---

## 3. Data Synchronization — `my/ct--update-window`

This is the core data maintenance function. Called:
1. At startup by `my/ct--update-all-windows`
2. On every redisplay by `my/ct--render-tabbar`
3. On every command by `my/ct--force-update`

### Algorithm

```
INPUT:  window
OUTPUT: (side effect) updates window's :groups, :selected, :mru

1. Read existing :groups, :selected, :mru from window parameter (or init to nil)
2. Get all visible buffers via my/ct--visible-buffers
3. For each visible buffer b:
   a. Determine b's group via my/tab-group-for-buffer
   b. If b's group exists in groups but b is not in it: append b
   c. If b's group does NOT exist in groups: create new group entry
   d. If b's group exists in mru but b is not in it: append b to MRU
   e. If b's group does NOT exist in mru: create new MRU entry
4. Remove killed buffers from all groups and MRU entries
5. Remove empty groups and MRU entries
6. Ensure each group has a selected buffer (default: first buffer in group)
7. Save :groups, :selected, :mru back to window parameter
```

### Key invariant

The MRU list for each group must contain exactly the same live buffers as the
groups list for that group, but in a different (MRU) order. Step 3d ensures
buffers from the groups list are added to the MRU list if missing.

---

## 4. Tab Rendering Pipeline

### 4.1 Header Line Format

The header-line-format (or tab-line-format) is set to a list of two `:eval` forms:

```elisp
'( (:eval (my/ct--eval-group-icon))
   (:eval (my/ct--eval-tabbar)) )
```

These are evaluated left-to-right during redisplay.

### 4.2 Render Window Resolution — `my/ct--resolve-window`

During redisplay, Emacs evaluates each window's header-line independently. The
dynamic variable `my/ct--render-window` is bound by each `:eval` wrapper to
identify WHICH window is being rendered.

Resolution logic:
1. If `(current-buffer)` is the buffer of `(selected-window)`, use selected-window
2. Otherwise, try `(get-buffer-window (current-buffer) 'visible)`
3. Fall back to `(selected-window)` if ambiguous

This is correct during redisplay because Emacs sets `(current-buffer)` to each
window's buffer when evaluating its header-line.

### 4.3 Group Icon — `my/ct--group-icon`

Returns a propertized string like:

```
       3  
```

Components:
- `   ` — the group's Nerd Font icon (e.g. `` for Tools, `` for Code,
  `` for Buffers), propertized with `my/ct-group-icon` face
  (bg `#ff4400`, fg `#2b2b2b`, bold)
- `  ` — separator, same face
- `  3` — live line number from `(format-mode-line '("%l") nil win)`, right-justified
  to 4 columns, same face
- `  ` — right chevron terminator, same face

The line number is retrieved using `format-mode-line` with the CORRECT WINDOW
argument (the resolved render window), ensuring non-selected windows show their
OWN line number, not the selected window's.

### 4.4 Tab Label — `my/ct--tab-label`

Returns a propertized label string for a single buffer:

| State | Format | Example |
|-------|--------|---------|
| Selected, modified | ` 󰐗 bufname` | ` 󰐗 myfile.txt` |
| Selected, unmodified | ` bufname` | ` myfile.txt` |
| Unselected, modified | ` 󰐗 bufname ` | ` 󰐗 myfile.txt ` |
| Unselected, unmodified | ` bufname ` | ` myfile.txt ` |

- `` — powerline arrow prefix (selected only)
- `󰐗` — modified marker (in `#ff4400`)
- Face: `my/ct-tab-selected` (bg `#8C8C8C`) or `my/ct-tab-unselected` (bg `#5C5C5C`)

### 4.5 Tab Bar — `my/ct--render-tabbar`

Builds the complete tab bar by:

1. Call `my/ct--update-window` to ensure fresh data
2. Read `:mru` from window parameter
3. Find the current buffer's group
4. Get the MRU-ordered buffer list for that group
5. Filter to live buffers only
6. For the first buffer: render a tab label
7. For each remaining buffer: append separator (`  ` + ` `) + tab label
8. Colorize the separator strings with the unselected background

Returns a list of propertized strings. Emacs concatenates these into the
header line.

### 4.6 Separator Coloring

The separators `  ` and ` ` between tabs are propertized with a hardcoded
background of `#5C5C5C` (matching the unselected tab color). This is a
simplification — ideally the separator after the selected tab would use
`#8C8C8C`, but the current code applies the same color to all separators.

---

## 5. Live Update — Post-Command Hook

### 5.1 `my/ct--force-update`

Runs after EVERY command (registered via `post-command-hook`):

```
1. Get selected-window and current-buffer
2. Call my/ct--update-window to sync data
3. Find the current buffer's group in the MRU list
4. If found:
   a. Remove buffer from its current position in MRU
   b. Prepend buffer to front of MRU list
   c. Save updated MRU
   d. Update selected buffer for this group to current buffer
5. Call force-window-update to trigger redisplay
```

This means every time you switch buffers (via mouse click, C-x b, or tab cycle),
the MRU list is updated to put the new buffer at the front.

### 5.2 Performance

`my/ct--update-window` runs on every command. It scans all visible buffers
(typically 5-50) and updates data structures. For most commands where no buffer
has changed, the update is a no-op (all buffers already exist in their groups).
The O(n) scan cost is negligible for typical buffer counts.

---

## 6. Tab Cycling — C-TAB / M-TAB

### 6.1 `my/ct--cycle`

```
INPUT:  optional BACKWARD flag
OUTPUT: switches to next/previous buffer in MRU list

1. Get the current buffer and its group
2. Get the MRU list for that group from the window parameter
3. Find the current buffer's position in the MRU list
4. Calculate the next index (forward: pos+1, backward: pos-1, wrapping)
5. Switch to the buffer at that index via switch-to-buffer
6. The post-command-hook (my/ct--force-update) handles MRU reordering
```

### 6.2 Keybindings

Registered in `centaur-tabs-mode-map`:

| Key | Command | Action |
|-----|---------|--------|
| `M-TAB` | `my/ct--forward` | Next tab in MRU order |
| `C-TAB` | `my/ct--forward` | Next tab in MRU order |
| `C-S-<iso-lefttab>` | `my/ct--backward` | Previous tab in MRU order |

The minor mode `centaur-tabs-mode` is enabled solely to provide this keymap.
We do NOT use any other centaur-tabs package functionality.

---

## 7. Window Lifecycle

### 7.1 Startup

```
File loaded →
  (centaur-tabs-mode t)           enable minor mode (for keymap)
  header-line-format set          two :eval forms
  (my/ct--update-all-windows)    initialize data for each window
  (force-window-update)          trigger first redisplay
```

### 7.2 Window Deletion

When a window is deleted, the `window-deletions-functions` hook runs a lambda
that sets the window parameter to nil, allowing garbage collection.

### 7.3 New Windows

When a new window is created (split, etc.), its header-line-format inherits the
default value set by our `set-default` call. The first redisplay calls
`my/ct--render-tabbar` which calls `my/ct--update-window`, initializing the
new window's data.

---

## 8. Faces

| Face | Purpose | Background | Foreground |
|------|---------|-----------|------------|
| `my/ct-tab-selected` | Selected tab | `#8C8C8C` | `#2b2b2b` |
| `my/ct-tab-unselected` | Unselected tab | `#5C5C5C` | `#2b2b2b` |
| `my/ct-group-icon` | Group icon segment | `#ff4400` | `#2b2b2b` bold |
| `my/ct-overflow` | Overflow indicator | `#2b2b2b` | `#ff4400` bold |
| `my/ct-modified` | Modified marker | (none) | `#ff4400` |

---

## 9. File Layout

| Section | Lines | Content |
|---------|-------|---------|
| 1 | ~17-51 | Custom faces |
| 2 | ~57-84 | Buffer grouping: categories, group-for-buffer |
| 3 | ~90-125 | Per-window data: get-data, groups, selected, mru accessors |
| 4 | ~131-190 | Buffer list + window update |
| 5 | ~196-255 | Tab rendering: tab-label, render-tabbar |
| 6 | ~261-293 | Group icon rendering |
| 7 | ~297-310 | Header-line eval wrappers + render window resolution |
| 8 | ~316-345 | Tab cycling functions + keybindings |
| 9 | ~351-380 | Activation (centaur-tabs-mode), format setup, hooks |
| 10 | ~386-395 | Legacy tab-label fallback |

---

## 10. Key Design Decisions

### Why no centaur-tabs internals?

The centaur-tabs package was designed with GLOBAL state: tabsets are interned in
a global obarray, caches are global hash tables, and buffer groups are stored in
a global list. Making per-window tabs requires fighting this architecture.

By building from scratch, we have:
- True per-window independence (each window has its own obarray-equivalent in
  the window parameter)
- No cross-window cache pollution
- Full control over the rendering pipeline
- Simpler debugging (all data is in one window parameter)

### Why window parameters instead of a hash table?

Window parameters are automatically cleaned up when a window is deleted (via
`window-deletions-functions`). They're also naturally per-window — you don't
need to look up "which window" when reading/writing data during redisplay.

### Why the dynamic variable trick?

During redisplay, Emacs evaluates header-line-format for each window sequentially.
There is no built-in Emacs Lisp way to ask "which window's header-line is
currently being evaluated?" The dynamic variable `my/ct--render-window` solves
this by being bound in the `:eval` wrapper function before any rendering code
runs.

### Why no overflow handling (yet)?

The current rendering code builds a list of tabs without checking terminal width.
If there are more tabs than fit, the header line will overflow and some tabs
will not be visible. Overflow truncation would require:
1. Measuring each tab label's width (via `string-width`)
2. Computing available width (via `window-width`)
3. Dropping tabs from the right until the total fits
4. Adding an overflow indicator (e.g., ` 󰲢 N`)

This is straightforward to add but was deferred for clarity.
