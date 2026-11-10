# PLAN — cooked terminal integration (branch: `cooked`)

Goal: replace ghostel with [cooked](https://github.com/vodik/cooked) as the terminal
emulator, re-implementing the orchestration layer from `ghostel/ghostfire.el` on top of
cooked's API, and re-pointing every dependent file. This branch is throwaway/testing; no
revert path or verification gate is required by the user.

## Decisions (confirmed with user)

1. **Scope** — new `cooked/cooked.el` module first; full re-pointing of dependents.
2. **broot** — fully ported onto cooked's API (no two-terminal coexistence).
3. **evil** — drop `evil-ghostel` in favor of `cooked-evil`.
4. **Wholesale swap** — cooked replaces ghostel everywhere.
5. **Drop** every orchestration mechanism cooked provides natively (compose buffer
   — confirmed, its `C-c C-m`/`t e` bindings are removed; `/proc` forensics; semi-char
   exceptions; statuscolumn hack).
6. **Rename** everything `ghostel-*`/`ghostfire-*` → `cooked`-appropriate names.
7. **Ghostfire** — keep the zoxide/consult/embark pipeline; only swap the send primitive.
8. **Nix** — `cargo` 1.98.0 already present (verified). The native core self-builds on
   first `M-x cooked`.
9. **No verification gate** — testing branch.
10. **Layout** — `cooked/cooked.el`, loaded from `init.el` via `my/load-module`.

---

## API map — ghostel → cooked (verified against cooked's source)

These are the exact replacements. All symbols below were read from the cooked checkout
(`/tmp/cooked-src`) on the day this plan was written.

| Concern | ghostel | cooked |
|---|---|---|
| Mode | `ghostel-mode` (also `broot-mode` derives from it) | `cooked-mode` (derives from `comint-mode`) |
| Spawn command | `(ghostel t)` / `ghostel-exec` | `(cooked &optional new command)` |
| Spawn at dir | bind `default-directory` around `(ghostel t)` | `(let ((default-directory cwd)) (cooked t))` |
| Send string | `ghostel-send-string` | `cooked-send-string` (or `cooked--send-to-child` low-level) |
| Send key | `ghostel-send-key "escape"` | `cooked-send-key` / `cooked-send-meta-key` |
| Live process? | `(process-live-p ghostel--process)` | `cooked--live-session` |
| Buffer-local process var | `ghostel--process`, `ghostel--term`, `ghostel--pid` | `cooked--session` (opaque struct, not a process object) |
| Working dir | `ghostel--get-pwd` (OSC 7) | **native**: OSC 7 writes `default-directory` + `list-buffers-directory` |
| Kill-on-exit | `ghostel-kill-buffer-on-exit` | `cooked-kill-buffer-on-exit` (defaults `nil`) |
| Buffer name | `ghostel-buffer-name` | `cooked-buffer-name` = `"*cooked: %p*"` (`%p` process, plus `%d`/`%t`/`%h`) |
| evil | `evil-ghostel` | `cooked-evil` (auto state sync, `[[`/`]]`, `vic`/`vac`) |
| Input modes | `semi-char`/`char` + `ghostel-keymap-exceptions` | none — automatic (line discipline + OSC 133) |
| Width correction | `my/ghostel-adjust-window-size` | none — native reflow on resize |

Key behavioral difference to remember: **cooked is `comint`-derived and owns the input
line at a prompt.** `cooked-send-string` will `user-error` if Emacs owns the line ("type
directly instead"). This affects the "cd the terminal from outside" pattern — see the
`broot` and zoxide sections below.

---

## File-by-file changes

### 1. NEW `cooked/cooked.el` (main work)

Mirror `ghostel/ghostfire.el`, reimplemented on cooked. Contents:

- **`use-package cooked`** — install via `package-vc`:
  ```elisp
  :vc (:url "https://github.com/vodik/cooked" :lisp-dir "lisp" :rev :newest)
  :commands (cooked cooked-other-window)
  :config
    (require 'cooked-evil)
    (require 'cooked-shell-completion)
    (require 'cooked-next-error)
    (require 'cooked-command-decorations)
    ;; omit: cooked-project (we keep our own indexed spawning), cooked-process (build
    ;; integration is out of scope for this branch), cooked-osc-eval (security surface),
    ;; cooked-file-link (nice-to-have, defer).
  ```
  No `evil-ghostel`, no `semi-char`, no `ghostel-keymap-exceptions`, no `ghostel--adjust-size`.

- **`my/cooked-working-dir`** — thin wrapper: since OSC 7 updates `default-directory`
  natively, this is just a documented shim returning `default-directory` in `cooked-mode`
  (kept so call sites stay readable and in case a fallback is needed later).

- **`my/cooked-next-available`** — same index-scan logic, but match the new separator
  (see naming below).

- **`my/cooked-new`** — indexed spawn:
  ```elisp
  (let ((default-directory cwd))
    (cooked t))            ; prefix = always a fresh session (matches ghostel's "new")
  (rename-buffer (my/cooked--name index my/cooked-name-syncing-label) t)
  (my/cooked--schedule-relabel (current-buffer))
  ```
  The `/proc`-free relabel is driven purely by cooked's command hooks (below).

- **`my/cooked-new-dispatch`** + `my/cooked-new-dispatch-alist` — unchanged shape;
  re-pointed handlers.

- **`my/cooked--mru-terminal-buffer`** — use `cooked--live-buffers` (already returns
  most-recent-first live sessions) instead of `process-live-p` + `ghostel--process`.
  Keep the `(not (derived-mode-p 'broot-mode))` exclusion.

- **`my/cooked-cd-from-broot`** — the tricky one. Because cooked owns the line at a
  prompt, `cooked-send-string "cd …\n"` will refuse. **Approach (decide at impl time):**
  send the line as *input* rather than raw bytes. Since the shell is at a fresh prompt,
  writing `cd <dir>\n` is exactly a submitted input line. Use the same mechanism
  `cooked--send-input-string` uses, or fall back to `cooked-send-string` after verifying
  the line is empty. Verify empirically; if ownership blocks this, the fallback is
  `cooked-here` (spawn/new session rooted at dir) instead of reusing the MRU terminal.

- **`my/cooked-new-from-broot`** / **`my/cooked-new-from-grease`** — same, with
  `(cooked t)` spawn and `my/cooked-new`.

- **Command-hook relabel** — replace the entire OSC 133 + `/proc` tpgid forensics block
  (`my/ghostel--anchor-pid`, `--tpgid`, `--read-comm`, `--fg-name`, `--refresh-name`,
  `--chase-name`, `--on-command-start/finish`, fallback poll) with cooked's own command
  records. Concretely:
  - `my/cooked--schedule-relabel` stays only for the initial "spawn → read label" race.
  - Label source = cooked's per-command record (look up the buffer-local variable cooked
    exposes for the current command's foreground process name; if none is exposed, use
    `cooked--live-session` state or fall back to a single `/proc` read off the session
    child pid — but **do not** re-introduce the chase/poll machinery).
  - Hook into `cooked-state-change-hook` (exists, `defcustom` in source around line 792)
    rather than ghostel's `ghostel-command-start-functions`.
  - Drop `my/ghostel-name-fallback-poll-interval` and the fallback timer entirely.

- **Dropped entirely** (cooked provides natively): compose buffer
  (`my/ghostel-compose-*`), semi-char exceptions block, statuscolumn width hack
  (`setq-default window-adjust-process-window-size-function`), and the
  `my/ghostel--grease-toggle-advice` OSC-7 wrapper (unnecessary — `default-directory` is
  already live).

- **Ghostfire (zoxide) pipeline** — carried over and renamed (see §6). Only the send call
  changes: `ghostfire-travel`'s final `ghostel-send-string (format "cd %s && clear\n" …)`
  becomes the cooked "submit as input" path (same ownership caveat as broot above). The
  consult/embark/`zoxide` machinery is terminal-agnostic and stays byte-identical aside
  from symbols.

### 2. `cooked/cooked.el` — naming (rename everything for clarity)

Renames (mechanically, but note the `ghostfire-*` names are referenced by `broot.el` and
`keybinds.el`, so do them in lockstep):

- `ghostel-*` → `cooked-*`; `my/ghostel-*` → `my/cooked-*`.
- `ghostfire-*` → `cooked-travel-*` (avoid collision with cooked's own `cooked-*`
  namespace, and it reads clearly as "directory travel").
- Package-local namespace suggestion:
  - `my/ghostel-new` → `my/cooked-new`
  - `my/ghostel-new-dispatch` → `my/cooked-new-dispatch`
  - `my/ghostel-cd-from-broot` → `my/cooked-cd-from-broot`
  - `my/ghostel-buffer-list` → `my/cooked-buffer-list`
  - `my/ghostel-spawn-at-index` → `my/cooked-spawn-at-index`
  - `my/ghostel-working-dir` → `my/cooked-working-dir`
  - `ghostfire-travel` → `cooked-travel`
  - `ghostfire--check-deps` → `cooked-travel--check-deps`
  - `ghostfire-consult-builder/format/map` → `cooked-travel-consult-*`
  - `ghostfire-embark-add/subtract`, `ghostfire-score-face`, etc. → `cooked-travel-*`

### 3. `init.el`

- Replace the load line (currently line 441–442):
  ```elisp
  ;; Ghostel terminal emulator — all config lives in ghostel/ghostfire.el
  (my/load-module "ghostel/ghostfire.el")
  ```
  with:
  ```elisp
  ;; cooked terminal emulator — all config lives in cooked/cooked.el
  (my/load-module "cooked/cooked.el")
  ```
- Optionally delete `ghostel/ghostfire.el` from the tree (or leave it; not loaded).
- No Nix change needed — `cargo` is on PATH (verified 1.98.0).

### 4. `broot/broot.el` (largest re-point; deepest coupling)

- `define-derived-mode broot-mode ghostel-mode "Broot"` → `cooked-mode`.
- `declare-function` block: `ghostel-mode/exec/send-string/--process` → cooked equivalents
  (`cooked-mode`, `cooked`, `cooked-send-string`, `cooked--session`).
- The spawn path: replace `(ghostel-exec buf broot-exe nil)` — ghostel's "run arbitrary
  program with no shell" — with cooked's equivalent. **This is the main open question:**
  cooked's `(cooked new command)` runs a *command via shell* (`cooked--shell-invocation`),
  so broot will likely run as `broot-exe` via `/bin/sh -c`. Verify broot's TUI (alternate
  screen, kitty graphics) still works through cooked's shell path; if not, investigate
  cooked's lower-level `cooked--start` (argv-direct) entry. Likely the simplest correct
  call is:
  ```elisp
  (let ((default-directory ...))
    (cooked t (list broot-exe)))   ; or the raw-argv variant
  ```
- Replace `ghostel--pid` reads in `my/broot-sync-default-directory` (line ~207) with the
  cooked session's child pid (whatever cooked exposes for `cooked--session`; if none,
  read it off the session struct — see `cooked--live-session`).
- Drop `ghostel--adjust-size` call (cooked handles sizing/reflow).
- The `my/ghostel-cd-from-broot` / `my/cooked-cd-from-broot` interplay and the
  `ghostfire-*`→`cooked-travel-*` zoxide pipeline call sites (line ~242+) get renamed and
  re-pointed in lockstep with §2.
- The "broot-mode before spawn, ghostel refuses mode changes on live buffers" comment
  (line ~32) — verify cooked has the same constraint; if cooked is more permissive, the
  ordering hack can be simplified (note it but don't over-engineer on a test branch).

### 5. `consult-buffer.el`

- `my/consult-ghostel-source` → `my/consult-cooked-source`; `my/ghostel-spawn-at-index` →
  `my/cooked-spawn-at-index`; `my/ghostel-buffer-list` → `my/cooked-buffer-list`.
- `my/consult-source-buffer-no-ghostel` → `...-no-cooked`; `(derived-mode-p 'ghostel-mode)`
  → `'cooked-mode`.

### 6. `keybinds.el`

- `"t e"` → `my/cooked-compose` → **delete this binding** (compose buffer dropped).
  Replace with nothing, or an equivalent cooked command (e.g. `cooked-send-string`) if the
  user wants a send-hoc key — decide at impl time; default to removing the binding.
- `"M-t"` → `my/cooked-new-dispatch`.
- `"M-z"` → `my/zoxide-travel-dispatch` → rename to `my/cooked-travel-dispatch` (and its
  internal `ghostfire-travel`→`cooked-travel`, `my/zoxide-travel-to-broot`→
  `my/cooked-travel-to-broot`, `my/zoxide-travel-to-dired`→`my/cooked-travel-to-dired`).
- `C-c C-m` → `my/ghostel-compose` → **remove** (compose gone).
- Evil ESC bind (`evil-define-key 'normal evil-ghostel-mode-map` … `ghostel-send-key
  "escape"`) → re-point to cooked's normal-state map; but **cooked-evil already handles
  state switching**, so this manual ESC-forward may be unnecessary. Evaluate and likely
  delete.
- `derived-mode-p 'ghostel-mode` checks in the dired/`C-e` handler (lines ~286, ~293) →
  `'cooked-mode`.

### 7. `panes.el`

- `(dolist (hook '(ghostel-mode-hook vterm-mode-hook)) …)` (line 94) →
  `'(cooked-mode-hook …)`, keeping `vterm-mode-hook` if vterm is still present.

### 8. `MRU-tabs.el`

- `("Ghostel" "" ghostel-mode)` (line 107) → `("cooked" "" cooked-mode)` (adjust label
  glyph if desired).

### 9. `custom.el`

- Remove `ghostel` from the `custom` list of packages (line 8); add `cooked`.

---

## Open questions / implementation-time decisions

These are deliberate `TODO(impl)` notes, not blockers — resolve empirically while coding.

1. **Send-a-line-from-outside** — whether `cd <dir>\n` to a cooked prompt goes through
   `cooked-send-string` (raw) or must be submitted as input. Determines
   `my/cooked-cd-from-broot` and `cooked-travel`. Fallback if ownership blocks: spawn via
   `cooked-here`/new session instead of reusing MRU.
2. **broot spawn** — `(cooked t (list broot-exe))` vs raw-argv entry; and whether cooked's
   shell wrapper breaks broot's alternate-screen / kitty graphics. This is the single
   highest-risk item in the port.
3. **Relabel source** — exact cooked variable/slot exposing the current foreground command
   name; if none, one `/proc` read off the session pid, no chase machinery.
4. **`cooked-evil` vs existing `evil-ghostel` hook** — confirm `evil-ghostel-mode` is fully
   unloaded so nothing fights `cooked-evil`'s state sync.
5. **`cooked-kill-buffer-on-exit` default `nil`** — broot currently relies on ghostel
   auto-killing the buffer on exit (`ghostel-kill-buffer-on-exit`); if broot should still
   die with its process, set `cooked-kill-buffer-on-exit` for `broot-mode` buffers.

---

## Build / runtime notes

- Rust 1.98.0 present; cooked builds the native core via `cargo` on first `M-x cooked`
  (~1 min, one-time). Ensure `cooked` repo stays on disk intact (`Cargo.toml`,
  `terminfo/`, `shell-integration/`) — `package-vc` keeps it via the `:lisp-dir` clause,
  but do **not** use a `:files` clause that strips the native bits.
- Emacs 31.1 (verified) satisfies the 29.1+ requirement; confirm dynamic module support is
  compiled in (it already was for ghostel's module, so it is).

## Suggested commit sequence

1. Add `cooked/cooked.el` (spawn + naming + dispatch + zoxide pipeline), rename symbols.
2. Re-point `init.el` load line; leave `ghostel/ghostfire.el` in place but unloaded.
3. Re-point `consult-buffer.el`, `panes.el`, `MRU-tabs.el`, `custom.el` (mechanical).
4. Re-point `keybinds.el` (drop compose/ESC bindings).
5. Port `broot/broot.el` (the hard one) — do last, on top of a working cooked base.
6. Delete `ghostel/ghostfire.el` once broot is confirmed working.

Verify at each step with `M-x cooked`, spawn at an index, `M-t` from a buffer and from
broot, `M-z` zoxide travel, and a full-screen TUI (`htop`/`vim`) to confirm key
forwarding and evil state switching.
