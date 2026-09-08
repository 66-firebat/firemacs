# Plan — Broot → Emacs: query broot's current directory on demand

Status: **implemented** (further revision after review). Filename corrected per
answer: `broot-emacs-default-directory.md`.

## Goal

Give Emacs Lisp a way to ask a broot session *"what directory are you rooted
at right now?"* at the moment of the call — **no polling, no timers, no hooks,
no background machinery**. Callers (e.g. `my/consult-ripgrep-with-jump`)
refresh the broot buffer's `default-directory` from broot's live process
directory just before they need it.

## Background / terminology

- A broot session = a Ghostel terminal buffer in `broot-mode` whose process
  **is** broot (spawned with `ghostel-exec`, no shell). The buffer's
  `default-directory` is set at spawn time by `my/broot--open` and otherwise
  goes stale as you navigate.
- "Directory in broot" = the focused panel's root. Entering/focusing a
  directory makes it the new root.
- Broot keeps its **own process working directory** synced to the focused
  panel's root (config knob `update_work_dir`, default on — the feature
  requested in https://github.com/Canop/broot/issues/813). So at any instant,
  `/proc/<pid>/cwd` *is* "the directory in broot". **Verify empirically with
  broot 1.57 in the live setup** (set `update_work_dir: true` in
  `~/.config/broot/conf.hjson` if it turns out to be off).
- Ghostel's shell integration (OSC 7) is **not** applied to `ghostel-exec`
  sessions, and broot 1.57 emits no OSC 7 anyway, so this is read Emacs-side.

## Design (final)

Two small functions in `broot/broot.el` (section: “On-demand
working-directory query”), Linux-only via procfs:

1. **`my/broot-current-directory` (&optional buffer)** — pure query.
   - `BUFFER` defaults to the current buffer; must be a live `broot-mode`
     session.
   - Reads `(file-symlink-p (format "/proc/%s/cwd" pid))` where `pid` =
     buffer-local `ghostel--pid` (the native broot child).
   - Returns the directory **with a trailing slash** (`default-directory`
     style), or **nil**.
   - Failure rules: not a broot buffer → silent nil.  Broot buffer but the
     process can't be found (`ghostel--pid` nil, process gone, or procfs
     unreadable) → a `message` in the log explaining the failure, then nil.
2. **`my/broot-sync-default-directory` (&optional buffer)** — convenience
   wrapper: query, and on success `setq-local default-directory` in that
   buffer, returning the new dir (nil otherwise, same message rules).

No defcustom, no poller, no focus hooks, no kill-hook bookkeeping: the
machinery from earlier plan revisions was dropped entirely.

## Caller wiring (demo)

`my/consult-ripgrep-with-jump` (keybinds.el) now resolves its search root as:

```elisp
(let ((target-dir (or (my/broot-sync-default-directory)
                      default-directory)))
  (consult-ripgrep target-dir))
```

- Invoked from inside a broot session (e.g. `S` in normal state) → the search
  runs against the directory currently focused in broot.
- Anywhere else → `my/broot-sync-default-directory` returns nil silently and
  the original `default-directory` behavior is unchanged.

## Edge cases

- Non-broot buffers: silent nil (fallback preserved).
- Multiple broot sessions: each query targets a specific buffer; only that
  buffer's `default-directory` is touched.
- Multi-panel broot: only the focused panel's root counts (broot's own
  process-cwd semantics).
- Symlinked paths: procfs returns the resolved physical path (documented).
- Process exited / buffer killed: pid gone → message + nil; nothing lingers.
- TRAMP/remote: not applicable to local `ghostel-exec` spawns.

## Validation (done)

- Byte-compiled `broot/broot.el` and `keybinds.el` clean.
- Batch tests (stub `ghostel-mode`, real pid): query returns
  `/…/` with trailing slash for a live pid; sync sets `default-directory`;
  non-broot buffer → silent nil; broot buffer with bogus/nil pid → logged
  message + nil.
- Live QA still needed by the user (real broot under Ghostel):
  1. open broot, Enter into a deep dir, run `S` (ripgrep w/ jump) — confirm it
     searches that dir;
  2. repeat after `:root`/backing up;
  3. confirm non-broot buffers behave as before.

## Considered and rejected

### An `emacsclient` verb in broot's config (automatic push)
- Broot verbs run only on user trigger — no "on focused-directory change"
  event exists, so no automatic push is possible.
- `update_work_dir` emits nothing; it only `chdir`s broot's process (the very
  signal procfs reads).
- broot 1.57 has no OSC 7 strings, so Ghostel's OSC 7 tracking never fires.
- As a manual push it would need shell-expanded `emacsclient -e` (quoting
  hazards) and per-session buffer disambiguation.

### A poller / focus-time auto-sync engine (earlier plan revision)
Replaced by the on-demand function per review: “no pollers — I'll call it
from my own functions” (see `my/consult-ripgrep-with-jump`).
