# Emacs → Neovim Feature-Parity Plan

This document is the **single source of truth** for porting the features from
the Emacs config (`~/nixos-dotfiles/git_repositories/emacs`) into the Neovim
config (`~/nixos-dotfiles/git_repositories/nvim`). It is deliberately written
to be executed in **iterative phases**.

---

## 0. How this config is sourced (critical workflow fact)

The nvim config is wired through **home-manager** (see
`~/nixos-dotfiles/home/shared.nix`):

```nix
home.file.".config/nvim" = {
  enable = true;
  recursive = true;
  source = ../git_repositories/nvim;
};
```

This **copies the tree into the read-only Nix store** and symlinks the
*individual files* into `~/.config/nvim`. The directories under
`~/.config/nvim` are real; the files are symlinks into
`/nix/store/...-home-manager-files/.config/nvim/...`.

Consequences:

- **The git repo is the source of truth.** All edits go to
  `git_repositories/nvim/`, never to `~/.config/nvim/` (which is read-only).
- **Edits are NOT live.** After changing files in the repo you must run
  `home-manager switch` to regenerate the symlinks into a fresh store path.
- **No environment variable is needed** to make `nvim` source `init.lua` from
  the repo — home-manager already points `~/.config/nvim` at a copy of it. The
  shortest path to *live* symlinking (repo edits reflected immediately, no
  `switch`) would be to replace the `home.file` block with an
  `home.activation` live-symlink like the existing DMS one in `shared.nix`:

  ```nix
  home.activation.neovimConfig =
    lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      mkdir -p "$HOME/.config"
      ${pkgs.coreutils}/bin/ln -sfn \
        "$HOME/nixos-dotfiles/git_repositories/nvim" \
        "$HOME/.config/nvim"
    '';
  ```

  **This is a recommendation only — do not change `shared.nix` without
  explicit approval.**

> TODO (fireshark): decide whether to switch nvim to a live symlink like DMS.

---

## 1. Goals / rules established during Q&A

- **Full feature parity** with the Emacs config, prioritising the *custom*
  Emacs systems that have no obvious Neovim equivalent.
- **Do NOT re-shuffle existing nvim keybindings.** New functions are built
  **unbound**; fireshark binds them manually after probing behaviour.
- **All code lives in a split module layout** (see §3). `keymaps.lua` contains
  **only `vim.keymap.set(...)` bind lines**; every custom function moves out.
- **`.bak` files are left untouched** (referenceable, never modified/deleted).
- Leave as-is (already ≈ parity): `snacks.scroll`, modeline (`lualine` git
  branch + mode + diff), git tooling (gitsigns/fugitive/lazygit/diffview), LSP
  (native `vim.lsp` + trouble), Julia (jetls/molten/slime), Python (pylsp /
  basedpyright), completion (blink.cmp + copilot), AI (nvim-aider ≈ pi).
- **Out of scope / defer:** LaTeX live-preview + Sioyek inverse search
  (vimtex left as-is → TODO to configure later), Org mode (no faithful port).
- **cwd source:** use `vim.fn.getcwd()` / `vim.fn.expand("%:p:h")` instead of
  OSC-7 live-cwd tracking.

---

## 2. Cosmetic / behavioural divergences (documented, not ported)

| Emacs | Neovim status | Decision |
|-------|---------------|----------|
| `doom-modeline` git diff stats `+ N ↯ C ✕ D` | lualine `diff` (`//`) | leave as-is |
| modeline git branch/hash + truncation | `get_git_branch()` | leave as-is |
| `evil-cursor` per-state cursor **color** (OSC 12) | nvim `guicursor` shape only | leave as-is (shape via guicursor) |
| `neoscroll` 0.15/0.25/0.025s easing | `snacks.scroll` (100/200ms) | leave as-is |
| `panes` per-window border glyphs | `winborder="single"` | port *wrap/trunc glyph + vert color* only (§5) |
| `embark-act` `C-;` context menu | not ported | skip (see §7 note) |
| `orderless` fuzzy completion feel | blink.cmp fuzzy | leave as-is |

---

## 3. Target file layout (split modules)

```
git_repositories/nvim/
├── init.lua                      (unchanged)
├── lua/
│   └── config/
│       ├── keymaps.lua           # ONLY vim.keymap.set bind lines
│       ├── reusable_functions.lua # NEW — general-purpose functions (M = this module)
│       ├── statuscolumn.lua      # NEW — letter labels + marks + search counter + scrollbar + wrap + bump
│       ├── jumplist.lua          # NEW — global persisted jump ring
│       └── tabs.lua              # NEW — grouped MRU tabline
```

Every custom function is exported from its module. `keymaps.lua` requires the
modules it needs (e.g. `local M = require("config.reusable_functions")`,
`local jump = require("config.jumplist")`, `local sc = require("config.statuscolumn")`,
`local tabs = require("config.tabs")`) and calls the functions inside
`vim.keymap.set({...}, "...", M.some_fn, {...})`.

---

## 4. `reusable_functions.lua` — general-purpose functions

New file `lua/config/reusable_functions.lua`, returns a table `M`.

### 4.1 Refactor: move existing inline functions out of `keymaps.lua`

Functions currently inlined in `keymaps.lua` that **must move** into `M`
(`keymaps.lua` keeps only the `map(...)` bind call):

| Function | Current keymap | Notes |
|----------|----------------|-------|
| `M.open_broot` | `<M-e>` (currently remapped to oil) | spawn `:terminal broot` at `%:h` |
| `M.open_oil` | `<M-e>` | `:Oil` with fallback |
| `M.flash_jump_f` | `f` | the flash jump closure with `setreg("/")` + `histadd` |
| `M.exact_word_search` | `S` | `\<...\>` prompt search |
| `M.zoxide_fzf_to_oil` | `<M-f>` | zoxide→fzf→oil (to be superseded by §4.2 `M.zoxide_travel`) |
| `M.oil_open_terminal` | `<leader>cd` (oil only) | `:terminal` at oil cwd |
| `M.close_other_buffers` | `<leader>bo` | delete all but current |
| `M.open_julia_terminal` | (commented) | tmux julia vsplit |
| `M.open_tmux_vsplit` / `M.open_tmux_terminal` | (commented) | leave commented |

> TODO (fireshark): confirm whether to also move the `L`/`H` start/end-of-line,
> `J`/`K` move-line, `n`/`N` centre, and `C-d`/`C-u` centre *expression* maps.
> These are pure `vim.keymap.set` expressions (no named function), so they may
> stay in `keymaps.lua` as bind-only lines.

### 4.2 New functions (all unbound; expose from `M`)

| Function | Emacs source | Behaviour |
|----------|--------------|-----------|
| `M.smart_other_window` | `my/smart-other-window` | if one window → `vsplit` + show alternate buffer + focus; else `wincmd w` / `vim.api.nvim_set_current_win` |
| `M.smart_close_window` | `my/smart-close-window` | close current window; no-op if last window |
| `M.buffer_by_index` | `SPC b 0-9` (`my/buffer-goto`) | list buffers as `"N: name"`, digit seeds `vim.ui.input`/picker, jump |
| `M.switch_previous_buffer` | `SPC b r` (`my/switch-to-other-buffer`) | toggle A↔B via `vim.fn.bufnr("#")` / alternate buffer |
| `M.search_line_jump` | `s` (`my/consult-line-with-jump`) | push jumplist + `Snacks.picker.lines()` + seed `/` register |
| `M.search_ripgrep_jump` | `S` (`my/consult-ripgrep-with-jump`) | push jumplist + `Snacks.picker.grep()` (root = getcwd) + seed `/` |
| `M.zoxide_query` | `ghostfire--run` | run `zoxide query -ls`, parse `(score . path)` lines |
| `M.zoxide_travel` | `M-z` (`my/zoxide-travel-dispatch`) | Snacks-picker over zoxide results; terminal buf → `cd`; else → open oil at dir |
| `M.numbered_terminal` | `M-t` (`my/ghostel-new-dispatch`) | indexed `:terminal` named `<N>  ⟨label⟩`, lowest free index, no OSC 133 relabel |
| `M.toggle_file_manager_at_cwd` | `C-e` (`my/dired-from-terminal`) | toggle oil at `getcwd()`/`%:p:h`; if in oil → close & return to prev buffer |
| `M.gitsigns_stats` | — | **skipped per Q16 (option b)** — do not implement |

> Note: `M.search_line_jump` / `M.search_ripgrep_jump` must integrate with the
> **shared search state** (§6) and the **global jumplist** (§7): push a jump
> mark before opening the picker, and write the chosen query into the `/`
> register so `n`/`N`/`*`/`#` and the statuscolumn search-instance counter all
> agree.

---

## 5. `panes` parity (wrap/trunc glyph + vert divider)

Minimal, in `reusable_functions.lua` (a `M.setup_pane_glyphs()` function invoked
from `init.lua` or `options.lua`), matching Emacs `panes.el` spirit:

- `vim.opt.showbreak = "· "` (wrap glyph, already ≈ `placeholder`)
- `vim.opt.fillchars` — set `vert` divider char + `eob` (already `eob=" "`).
- Highlight `VertSplit` fg `#ff4400` (already done in
  `lua/config/highlight_groups/highlights.lua` → confirm/link).

---

## 6. `statuscolumn.lua` — full letter-label gutter (REPLICATE ENTIRELY)

New file `lua/config/statuscolumn.lua`. This is the **flagship** port of
`emacs/statuscolumn.el`. Runs on top of your existing
`statuscol.nvim` + `vai.nvim` (already wired in `lua/plugins/statuscolumn-vai.lua`).

Port **all** of these Emacs behaviours exactly:

1. **Letter jump labels** — visible lines get `a`–`z`, then punctuation
   (`.,@!#$%^&*()-+=[]{}:;<>?/~`), then multi-char fallback (`aa`…), via
   `vai.labels.build_labels()`. Non-current lines show the label; current line
   shows its absolute line number.

2. **Per-line Evil marks** — show `a`–`z`/`A`–`Z` mark chars in the gutter on
   their line (port `sc--build-mark-map`): read nvim marks via
   `vim.fn.getmark('a')` etc., map BOL→mark char. Recent-mark tracking (advice
   on `evil-set-marker`) becomes a `vim.on_key`/`User` hook that records the
   most-recently-set mark per line.

3. **Search-instance counter** — driven by **all** highlight navigation
   (`/`, `?`, `*`, `#`, `g*`, `g#`, `n`, `N`, and flash). Computed by re-matching
   the shared `/` register regex from buffer start to the current match,
   right-aligned 3-char (`1`, `2`, … `99+`), shown on the current line only.
   Must respect **flash**'s notion of the current match (§6.1).

4. **Scrollbar-thumb icon** — an 8-band Nerd Font "thumb" glyph derived from
   `(point) / (line-count)` (port `sc--slice-icon`), plus the line-position
   variant (`sc--line-slice-icon`).

5. **Wrap icon** — `watch` glyph on wrapped continuation lines (current vs
   non-current), replacing the line label.

6. **Current-line bump** — `┣` on the current line, `┃` on others
   (`StatusColumnBorderBump` / `StatusColumnBorder`), matching
   `sc--current-str` / `sc--lab-str`.

7. **Bolt icon during jump** — while a `;`/vai jump is active, show `bolted`
   instead of the scrollbar icon (`sc--jump-active`), and restore after.

8. **Rebuild on scroll / resize / tick** — port `sc--on-window-scroll`,
   `sc--on-pre-redisplay`, `sc--on-window-size-change` to nvim autocmds
   (`WinScrolled`, `VimResized`, `TextChanged`/`CursorMoved`, `WinEnter`).

### 6.1 Shared search state (flash ↔ native `/`)

Per Q11 (option b): flash, native `/`, `*`/`#`, `n`/`N` **share one source of
truth**. Implement a small `SearchState` in `statuscolumn.lua`:

- On `*`/`#`/`g*`/`g#`, nvim already sets `/`. Ensure flash's `f`/`/` also
  write the pattern to `/` (your current `f` closure already does
  `vim.fn.setreg("/", state.pattern.pattern)` + `histadd` — keep that, and make
  it the canonical path).
- The search-instance counter reads `vim.fn.getreg("/")`, re-syncs flash when
  flash is active, and counts matches up to `line(".")`.

---

## 7. `jumplist.lua` — global persisted jump ring (Q3/Q4 = option b)

New file `lua/config/jumplist.lua`. Ports `emacs/jumpring.el`:

- A **global** ring (one list shared by all windows), not the per-window native
  jumplist semantics that lose terminal/oil jumps.
- **Record jumps in every buffer type** — normal files, `terminal`, `oil`,
  dired-analog, `:help`, etc. Hook `CursorMoved`/`WinEnter`/`BufEnter` and the
  search/jump functions (`M.search_line_jump`, `M.search_ripgrep_jump`,
  flash `f`, `;`/vai) to push `(bufnr, line, col, file)` entries.
- **`C-o` / `C-i`** navigate back/forward (bind these yourself — leave the fn
  as `jump.backward()` / `jump.forward()`).
- **Persist across sessions** (Q4 = option b): serialize the ring on
  `VimLeavePre` to a file under `vim.fn.stdpath("state")` (e.g.
  `~/.local/state/nvim/jumplist.json`), restore on `VimEnter`, filtering out
  dead files — mirroring `emacs/jumpring.el` savehist logic.
- Integrate with the existing `folke/persistence.nvim`? No — keep the ring's
  own JSON store (self-contained, matches Emacs savehist independence). Document
  this clearly.

---

## 8. `tabs.lua` — grouped MRU tabline (Q9 = option a)

New file `lua/config/tabs.lua`. Ports `emacs/MRU-tabs.el`:

- Group buffers by `filetype`/`buftype` into the same categories (mapped to
  nvim equivalents):

  | Emacs group | icon | nvim match |
  |-------------|------|------------|
  | Code | `󰣕` | lua, python, go, rust, java, c/cpp, js/ts, css/scss, html, json/yaml/sql/nix/sh |
  | Grease / file mgr | `󰏇` | `oil` |
  | Docs | `` | markdown, text, (org n/a) |
  | Config | `` | conf/dotenv |
  | Dired / file tree | `󰙅` | oil (duplicate of Grease) — decide |
  | Ghostel / terminal | `` | `terminal` buftype |
  | Broot | `󰙅` | terminal buffers named `broot*` |
  | Tools | `` | fugitive/lazygit/diffview/help/qf |
  | Buffers | `` | catch-all |

- Render a **group icon + line-number segment + MRU-ordered tabs** with
  modified marker `󰑧`, overflow icons (`󰲠`…`󰲲` / `󰲭`), selected-tab highlight.
- Cycle via `tabs.forward()` / `tabs.backward()` (Emacs `M-h`/`M-l`); expose
  unbound.
- Integrate as a lualine `tabline` component (extend `lua/plugins/lualine.lua`
  tabline section) or a standalone bufferline component — **confirm in a later
  iteration** which surface you prefer.

---

## 8b. Global MRU redesign — unified numbering for tabs + picker

**Status: IMPLEMENTED (pending live verification).** Supersedes the numbering parts
of §8 (the grouped tabline itself survives; how it gets its *numbers* changes).

### Motivation

Two problems drove this:

1. **Terminals and files looked different** in the tab bar (`2  1  terminal` vs
   `3   arm_bringup.md`) because terminals carried their index inside the buffer
   name while files used a separate stable number. Goal: **one format for
   everything** — `2  arm_bringup.md`, `2  nvim`.
2. **The `<M-i>` Snacks picker showed the raw nvim `bufnr`**, which was wildly
   out of sync with the tab bar's numbers.

### Research: can we renumber nvim buffers? **No.**

Confirmed three ways — this is why the fix is a *display/tracking* layer, not a
bufnr rewrite:

- `:h buffer-reuse` — "Each buffer has a unique number and the number will not
  change within a Vim session."
- neovim/neovim#1117 ("Reset `:buffers` numbers") — **closed wontfix**;
  justinmk: "This would likely break many things. Plugins (and some users)
  expect buffer ids to be unique forever."
- Verified locally: `nvim_create_buf` takes no bufnr arg, `nvim_buf_set_numbers`
  does not exist, `bufadd` returns monotonically increasing ids.

**But the *display* is fully overridable:** `Snacks.picker.buffers` renders
`item.buf` in `Snacks.picker.format.buffer` (`picker/format.lua:645`), and
`opts.format` is a user-settable function (`picker/config/init.lua:166`). So the
picker can print **our** rank instead of the raw bufnr.

### Reference model: `git_repositories/spinner6`

spinner6 (`shell.qml` + `lib/spinner6-core.js`) keeps a single
`property var focusHistory: []` — **MRU-first, the single source of truth** —
with these mutations, which we mirror:

| spinner6 | semantics |
|----------|-----------|
| `moveToFront(addr)` | existing entry: splice out, `unshift` to index 0 |
| `addToFront(addr, …)` | new entry inserted at **index 1** (behind current) |
| `addToTail(addr, …)` | new entry `push`ed to the end (least recent) |
| `removeAddress(addr)` | splice out; **everything after shifts up** |

Index in that array *is* the displayed number.

### The change: one global MRU array, numbers = array position

Today `tabs.lua` has **two unrelated concepts**: `mru_ts` (timestamps, sorted
**per group** at render) and `stable_number` (creation order, rebuilt from
listed buffers). That split is the root cause of the desync.

New model: a single **global** MRU array; the tab index is its **1-based
position**, mutable, shifting on every change. A group's visible tabs may thus
show non-contiguous numbers (`1, 4, 9`) — that is **intended**, it tells you each
buffer's place on the *global* list.

### Decisions (all 25 Q&A answers)

**Numbering**

| # | Question | Answer |
|---|----------|--------|
| 1 | numbering scheme | **strictly 1-based position in the global MRU array; no gaps; shifts on every change.** (Supersedes the earlier "Option c: lowest-free-number reuse" answer.) |
| 2 | membership | **listed + named + non-scratch + `filetype == "oil"`**; terminals included. |
| 3 | tab ordering within a group | current buffer leftmost (it is always #1), remaining group tabs ascending by global rank. |
| 4 | current buffer in another group | **group follows the window's buffer** — no foreign-tab force-insert. |
| 5 | picker contents | all membership buffers in global MRU order, **starting at rank 2** (current excluded). |
| 6 | identity key | **bufnr**, with aggressive pruning (no name-based memory). |
| 7 | where a new buffer lands | **tail** (becomes #1 only when entered). |
| 8 | when to reorder | **every `BufEnter` on a member**, no filtering (transients get wiped → pruned). |
| 9 | prune event | **`BufWipeout` ONLY** — no redundancies. |

**Architecture**

| # | Question | Answer |
|---|----------|--------|
| 11 | where it lives | **new module `lua/config/mru.lua`**. |
| 12 | who owns `BufEnter` | **`mru.lua`**; `tabs.lua` becomes a pure reader. |
| 13 | API | `setup/touch/rank/list/list_excluding/is_member/refresh` (+ terminal cache). |
| 14 | membership timing | **pure predicate evaluated on demand** (no cached set). |
| 15 | superseded `tabs.lua` code | **comment out**, do not delete; clean up at the end. |
| 16 | picker implementation | **custom finder + custom format**, keeping Snacks UI/actions/preview. |
| 19/20 | terminal program cache | **lives in `mru.lua`** together with the 5s timer (both `tabs.lua` and the picker need it). |
| 25 | membership changing silently | acceptable: live predicate means it vanishes from tabs; reappears at its stale rank (a later `BufEnter` re-touches it anyway). |

**Flicker / picker-delete behaviour**

| # | Question | Answer |
|---|----------|--------|
| 21 | prune timing | **synchronous** inside `BufWipeout` (no `vim.schedule`) so `picker:refresh()` never sees stale ranks. |
| 22 | redraw on prune | **none** — no explicit redraw (avoids picker repaint flicker); the winbar re-evaluates naturally. |
| 23 | deleting the current buffer | expected: nvim switches → `BufEnter` → `touch` → ranks shift again. |
| 24 | `BufWipeout` handler body | **pure Lua table removal only** — no nvim API calls, cannot recurse. |
| 24b | edge | inside `BufWipeout` the buffer may already be invalid; pure-table removal sidesteps that entirely. |

### `lua/config/mru.lua` — API

```lua
M.setup()            -- augroup: BufEnter -> touch, BufWipeout -> prune (table-only)
M.touch(bufnr)       -- move to front (no-op if not a member)
M.rank(bufnr)        -- 1-based global index, or nil
M.list()             -- MRU-first bufnr array (membership + validity filtered)
M.list_excluding(b)  -- list() minus one bufnr (picker drops the current)
M.is_member(bufnr)   -- pure predicate: listed + named + non-scratch + oil
M.refresh()          -- force membership rebuild of the array
-- terminal foreground-program cache:
M.terminal_prog(bufnr)
M.term_poll_interval = 5000
```

### Terminal label = foreground program (tpgid)

Replaces the `term://<N>  terminal` self-label. A terminal tab renders
`2  nvim`, identical wrapper to files; the picker resolves terminals the same
way (option a: cached value, resolve on miss).

**Resolution algorithm** (verified empirically): read the shell's `tpgid` from
`/proc/<job_pid>/stat` **field 6**; if `tpgid == job_pid` -> use the shell's
`comm`; otherwise find the process whose `pgrp == tpgid` (via the shell's
`/proc/<pid>/task/<pid>/children`, cheap — **no full `/proc` scan**) and use its
`comm`.

> Verified: idle -> `bash`; `sleep 5` -> `sleep`. Note that the shell's own
> `tpgid` field DOES track the foreground job in nvim's pty (an earlier
> `pgrp`-scan variant failed, and a descendants-only variant went stale after
> process exit).

**Refresh policy:** cache + refresh on `TermEnter` / `BufEnter` / `FocusGained` /
`TermClose` / leaving the terminal buffer; plus a **5s timer keyed to the
focused window only** (configurable via `M.term_poll_interval`). On a tpgid
change, **force an immediate redraw of all winbars**.

### `tabs.lua` changes

- **Comment out** (keep for reference): `visible_buffers`, `mru_group`, `mru_ts`,
  `touch`, `stable_number`, `rebuild_stable_numbers`, `get_stable_number`.
- `tab_label`: `rank .. "  " .. name`; name = `mru.terminal_prog()` for
  terminals, basename for files, dir basename for oil.
- `render`: group from the **window's** buffer; group members ascending by
  global rank; current buffer is #1 so naturally leftmost; no force-insert.
- No terminal timer/logic here.

### `<M-i>` picker changes

Custom **finder** over `mru.list_excluding(current)` + custom **format** printing
`rank` instead of `item.buf`; ordered by rank starting at `2`; Snacks preview and
`dd`/`<c-d>` delete retained. Delete path: `Snacks.bufdelete.delete(buf)` ->
`BufWipeout` -> synchronous table removal -> `picker:refresh()` re-renders with
correct ranks (0 flicker).

### `init.lua`

Add `require("config.mru").setup()` next to `require("config.jumplist").setup()`.

---

## 9. Key-binding parity — reference table (apply manually)

Because we are **not** re-shuffling existing nvim keys, this is a reference for
you to wire by hand. Only the **left** column's *functions* are built (left
unbound); the `>` shows a suggested nvim lhs.

| Emacs (source of truth) | nvim function (built, unbound) | suggested bind |
|-------------------------|--------------------------------|----------------|
| `f` / `F` (avy char / timer) | `M.flash_jump_f` (flash already bound) | `f` / `F` |
| `;` / `gs` (line jump) | `vai.jump.start` (already) | `;` |
| `s` (consult-line) | `M.search_line_jump` | `s` |
| `S` (ripgrep) | `M.search_ripgrep_jump` | `S` |
| `n` / `N` (search + recenter) | existing `nzz`/`Nzz` | `n` / `N` |
| `C-o` / `C-i` (jumplist) | `jump.backward` / `jump.forward` | `C-o` / `C-i` |
| `C-a` (select all) | existing `ggVG` | `C-a` |
| `M-w` / `M-W` (smart window) | `M.smart_other_window` / `M.smart_close_window` | `M-w` / `M-W` |
| `M-t` (numbered terminal) | `M.numbered_terminal` | `M-t` |
| `M-z` (zoxide travel) | `M.zoxide_travel` | `M-z` (or `M-f`) |
| `M-e` (broot/oil toggle) | `M.open_oil` (existing) | `M-e` |
| `C-e` (file-mgr at cwd) | `M.toggle_file_manager_at_cwd` | `C-e` |
| `M-h` / `M-l` (MRU tabs) | `tabs.backward` / `tabs.forward` | `M-h` / `M-l` |
| `SPC b 0-9` (buffer index) | `M.buffer_by_index` | SPC b 0-9 |
| `SPC b r` (prev buffer) | `M.switch_previous_buffer` | SPC b r |

---

## 10. Phased execution order (checkboxes)

- [x] **Phase 0 — plan approval & workflow** (this file; live symlinks established).
- [x] **Phase 1 — `reusable_functions.lua` skeleton + refactor `keymaps.lua`**
  - [x] Create `lua/config/reusable_functions.lua`, export `M` (31 functions).
  - [x] Move existing inline functions out of `keymaps.lua` (§4.1).
  - [x] Leave `keymaps.lua` bind-only; `require` the module.
  - [x] Panes glyphs (`M.setup_pane_glyphs`) (§5).
- [x] **Phase 2 — `statuscolumn.lua`** — DONE (heavily customised beyond plan).
  - [x] `lua/config/statuscolumn.lua`: static circled/boxed labels, marks (square
        glyphs), mode indicator, gitsign-at-cell-2, `│` bump, direct render.
  - [x] Removed statuscol.nvim entirely; `vim.o.statuscolumn` set directly to
        `config.statuscolumn.render()` (no tick-gated cache).
  - [x] Re-bound `;` → `config.statuscolumn.jump()`; disabled vai.nvim.
  - [x] Marks: buffer-local `last-on-line` recency (synchronous via `m` wrapper),
        cross-buffer guard, stale-shada prevention (`delmarks` first).
  - [x] Disabled `marks.nvim` (it shadowed the `m` keybinding).
  - [x] Search-instance counter renders (shared `/` register + `v:hlsearch`).
  - [x] Line-number removed from gutter (relocation to header deferred/skipped).
- [x] **Phase 3 — `jumplist.lua`** — DONE.
  - [x] Create `lua/config/jumplist.lua` (global ring, push/backward/forward, JSON persist).
  - [x] Wire `setup()` in `init.lua` (VimEnter load + VimLeavePre save).
  - [x] Hook `jump.push()` into `f` (flash), `;` (statuscolumn), `s`/`S` search.
  - [x] Bind `C-o` → `jump.backward()` and `C-i` → `jump.forward()`.
  - [x] Marks (`'`/`` ` ``) push to the jump ring.
- [x] **Phase 4 — `tabs.lua`** — DONE (grouped MRU tabline via winbar).
  - [x] Per-window winbar tab bar; grouped by filetype; MRU ordering; current
        buffer always leftmost; rightmost tabs trimmed; nvim clips overflow.
  - [x] Group-count icon (reusable `buffer_count_icon`), stable 1..N buffer
        numbers, per-tab `󱗷` separators with independent highlight groups.
  - [x] lualine swapped to winbar/statusline as configured; filetype icon added
        to lualine segment A; segment-B caps.
  - [x] Removed: filetype icon + tab lead from tabline, overflow indicator, line
        number segment.
  - [x] Reusable `.filetype_icon`, `.buffer_count_icon`, `.current_group_count`,
        `.group_for_buffer` live in `reusable_functions.lua`; consumed by
        `tabs.lua` + `lualine.lua`.
- [x] **Phase 5 — search/jump functions** — DONE.
  - [x] `s` → `M.search_line_jump` (Snacks buffer-lines, seeds `/` register, opens instantly).
  - [x] `S` → `M.search_ripgrep_jump` (Snacks project grep, seeds `/` register).
  - [x] `seed_search()` helper (setreg + histadd + hlsearch).
  - [x] Operator-pending flash motion (`M.flash_motion`, bound on `f` in `o` mode: `df`/`yf`/`cf`).
  - [x] mini.surround scoped to VISUAL-only on `s`; nvim-surround disabled (`.bak`).
- [x] **Phase 6 — zoxide / terminal / file-mgr** — DONE.
  - [x] `M.numbered_terminal` — buffer-var indexed naming (`b:numbered_terminal_index`),
        `term://<N>  terminal` name; bound `<M-t>` (n,t).
  - [x] `M.terminal_vsplit` — current buffer left / live shell right at the
        file's dir (`:lcd` + bare `:terminal`); bound `<M-T>` (n,t).
  - [x] `M.oil_toggle` (replaces broot on `M-e`) — Emacs `my/broot-default-directory`
        analogue: in oil → close it; else → open oil at the origin dir, recording
        `b:oil_source` (tracked, NOT force-returned).  Terminal origin → uses the
        terminal's live cwd (`/proc/<pid>/cwd`).  Bound `<M-e>` (n,t).
  - [x] `M.toggle_file_manager_at_cwd` — implemented (unbound).
  - [x] `M.zoxide_query` / `M.zoxide_travel` — implemented (unbound; supersedes
        `M.zoxide_fzf_to_oil` on `<M-f>`).
  - [x] Fixed `current_file_dir` (`isdirectory() == 0`, not `not isdirectory()`;
        Lua treats 0 as truthy).
- [x] **Phase 7 — smart windows** — DONE.
  - [x] `M.smart_other_window` bound to `<M-w>` (n,t) — splits right showing the
        alternate buffer when there is one window, else focuses the other window.
  - [x] `M.smart_close_window` bound to `<M-W>` (n,t) — closes the current
        window, no-op when it is the last non-floating window (float-aware count;
        `winnr("$")` was misleading because it counts floats).
  - [x] `M.buffer_by_index` / `M.switch_previous_buffer` — **dropped** (not wanted;
        functions removed from `reusable_functions.lua`).
- [ ] **Phase 8 — manual keybinding wiring** (§9) + verify.
- [x] **Phase 9 — global MRU redesign** (§8b) — new `mru.lua` (single global
      MRU array, numbers = array position), `tabs.lua` becomes a pure reader,
      `<M-i>` picker gets a custom finder/format, terminal labels show the
      foreground program with a 5s focused-window poll.
  - [x] `lua/config/mru.lua` — `is_member` / `touch` / `add_to_tail` / `remove`
        / `refresh` / `list` / `list_excluding` / `rank` / `terminal_prog` /
        `terminal_fg_program` / `refresh_terminal_prog` / `pick_buffers`.
  - [x] Autocmds: `BufEnter`→touch, `BufNew`/`BufAdd`→tail, `TermOpen`→touch,
        `BufWipeout`→pure-table prune, `TermEnter`/`FocusGained`/`TermClose`→
        terminal cache, 5s focused-window `tpgid` poll + forced redraw.
  - [x] `tabs.lua` now reads `mru.rank()` / `mru.terminal_prog()`; old
        `visible_buffers`/`mru_ts`/`touch`/`mru_group`/`stable_number`/
        `rebuild_stable_numbers`/`get_stable_number` **commented out** pending
        the final cleanup pass.
  - [x] `<M-i>` → `mru.pick_buffers()` (custom `items`, `sort = false`,
        custom `format` printing the rank; no `source = "buffers"`, which
        would re-install Snacks' finder and discard our list).
  - [x] `init.lua` → `require("config.mru").setup()`.  ← **CURRENT**

### Picker previews (post-implementation refinement)

Snacks' picker **previews** the highlighted item by loading it into a preview
window, which fires `BufEnter` on that buffer — previously promoting it to #1
and desynchronising the picker's numbers from the tab bar.  Resolution
(2 further questions):

- **Preview must NOT reorder the MRU.**  `mru.touch()` returns early while any
  picker is active (`M.is_picker_active()`), so highlighting never promotes a
  buffer.  Verified: MRU is identical before/during/after the picker is open.
- **The tabline still tracks the preview** (display only).  `tabs.render()` calls
  `M.preview_buffer()` and, when the previewed buffer is a real MRU member in
  the *same group* as the window's buffer, treats it as "current" for that
  render: it becomes leftmost but keeps its true MRU rank number.
  Verified: previewing `b.txt` renders `2  b.txt  1  c.txt  3  a.txt`.
- Note the picker's preview window may hold an unrelated scratch buffer, so the
  override additionally requires `mru.rank(preview)` to be non-nil.

### Implementation notes / gotchas discovered

- `nvim_create_buf` cannot set a bufnr; renumbering is impossible (see above).
- A terminal's `buftype` is still `""` during its creating `BufEnter`, so
  `TermOpen` is required for terminals to enter the MRU list at all.
- The shell's `tpgid` (from `/proc/<pid>/stat` field 6) **does** track the
  foreground job under nvim's pty; a `pgrp`-scan variant did not, and a
  descendants-only variant went stale after the child exited.
- `Snacks.picker.pick` with `source = "buffers"` ignores `opts.items` entirely
  (it installs the source's own finder) — omit `source` when supplying `items`.
- Snacks drops custom fields from items during resolution, and its matcher
  re-sorts — hence `sort = false` and a rank snapshot taken at pick time.
- `:normal!`-based animations (snacks.scroll) must never run in a terminal
  buffer (terminal mode forbids re-entering normal mode).

---

## 10b. Extras built beyond the original plan

- [x] **`nvim-web-devicons` plugin spec** (`lua/plugins/nvim-web-devicons.lua`)
      with a custom `.hjson` icon override.
- [x] **Broot smart dispatch** (port of `emacs/broot.el`):
      `M.spawn_broot`, `M.broot_toggle`, `M.is_broot` (buffer-local `b:broot`
      flag), `M.terminal_cwd` (`/proc/<pid>/cwd`); full-size buffer; toggle
      returns to origin buffer; ESC quits; auto-close terminal on exit.
- [x] **Live symlinks** in `home/shared.nix` for `nvim`, `ghostty`, and `broot`
      (edits live; no rebuild).
- [x] **UI**: `WinSeparator` light grey; `fillchars.vert = '╎'`; lualine
      segment reorganisation (A=filetype icon, B=location/branch/diag + caps)
      and inverted cap colors; lualine mode/buffers segments blanked.
- [x] **Terminal**: `[Process exited]` auto-close via correct `TermClose`
      (uses `event.buf`, never the user's file buffer).
- [x] **Persistence/flash fixes**: removed buggy broot `BufLeave`/`TermClose`
      autocmds that killed the origin buffer; `redraw` no longer mutates state
      during render (no flashing tabline).
- [x] **Alt-key parity with terminal mode**: every Alt binding is `{ "n", "t" }`
      (`<M-e>` oil toggle, `<M-i>` buffers, `<M-k>` kill, `<M-r>` recent,
      `<M-t>` numbered terminal, `<M-T>` terminal vsplit).  `<M-CR>` (copilot,
      plugin-owned) mirrored commented in `keymaps.lua`.
- [x] **Oil integration**: oil buffers show the MRU tab header (oil no longer
      manages the winbar); `bufhidden = "wipe"` so navigation doesn't pile up
      hidden buffers; tab label shows the directory basename; oil buffers
      included in the tab list and in `<M-i>` (`hidden = true`).
- [x] **Spell leak fixed**: filetype spell autocmd now uses `vim.opt_local`
      (was `vim.opt`, leaking spell into every buffer).
- [x] **Snacks scroll**: terminals stay excluded (animation uses `:normal!`,
      illegal in terminal mode).
- [x] **Git source in oil buffers**: `oil-git.nvim` (own `git status` +
      `OilGit*` highlights), not gitsigns (gitsigns does not attach to oil).

---

## 11. Open TODOs / deferred

- [ ] LaTeX: configure vimtex Sioyek forward/inverse search + `latexmk -pvc`
      live preview (Emacs `auctex.el` parity) — **explicit TODO reminder**.
- [ ] Org mode: out of scope (no nvim port).
- [ ] `.bak` files: left untouched.
- [x] Switched nvim/ghostty/broot to live symlinks (§0).
- [x] `tabs.lua` surface confirmed: standalone winbar (not lualine tabline).
- [x] `panes` vert divider glyph: `╎`, light grey `#8c8c8c`.

---

## 12. Definitions / notes for implementation

- **"push a jump mark"** = record `(bufnr, line, col)` into `jumplist.lua`'s
  global ring *before* the navigation action, so `C-o` returns to it.
- **"seed `/` register"** = `vim.fn.setreg("/", query)` and
  `vim.fn.histadd("search", query)`, so `n`/`N`/`*`/`#` and the
  search-instance counter see the same pattern.
- **cwd** = `vim.fn.getcwd()` fallback `vim.fn.expand("%:p:h")`.
- **Unbound** = functions exist in their module but no `vim.keymap.set` is
  emitted; fireshark binds them manually.
