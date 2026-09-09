# ghostel-process-name — live foreground-process name in ghostel buffer names

**Target:** `ghostel/ghostfire.el` (firemacs repo; not the nested grease repo — no upstream-PR
concerns). Two rename sites + new helper section.
**Affected consumers:** `consult-buffer.el` (lists buffer names), `MRU-tabs.el` (tab label is the
buffer name verbatim), `jumpring.el` (stores non-file jump targets *by buffer name* — see R4),
`broot/broot.el` (own `"broot"` naming + reads buffer-local `ghostel--pid` — see D5), keybinds
(prefix scan in `my/ghostel-next-available`).
**Status:** IMPLEMENTED in `ghostel/ghostfire.el` (byte-compiles clean) — see "Implementation
notes" below. Decisions taken: D1, D2, D3, D4 (revised after Phase 0 recon — event-driven), D5,
D6, D7, Q1–Q8.
**Date:** 2026-07 (implemented; not yet committed — user commits manually).

## Objective

Replace the PID component of ghostel buffer names with the name of the process currently running
in that terminal:

```
today:    "1  <PID>"        e.g. "1  19950"
goal:     "1  <process>"    e.g. "1  bash", then "1  vim" while editing, back to "1  bash"
```

- The **index** and the separator glyph stay byte-identical to today (D6).
- "Currently running process" = the **foreground process group** of the terminal's pty: at the
  shell prompt that is the shell itself; while a job runs it is that job's leader (D1, D2).
- The PID stays reachable buffer-locally as `ghostel--pid` (unchanged — broot and debugging rely
  on it, D3). Nothing in the name is parsed for the PID today, so dropping it from the name is
  safe (verified: no `buffer-name`-parsing consumers besides the index-prefix scan in
  `my/ghostel-next-available`, ghostfire.el:110-120).

## Phase 0 recon — findings (installed ghostel 2026-09-02, `~/.emacs.d/elpa/ghostel-20260902.1753`)

Read from `ghostel.el` / `ghostel-shell.el` source:

1. **`ghostel--pid` is the real terminal child PID on BOTH pty paths** (ghostel.el:4063-4065,
   4146, 4169-4170):
   - *Native PTY* (`ghostel-use-native-pty`, libghostty): `ghostel--process` is an event-pipe
     stand-in, but `ghostel--pid` is the PID the Zig module reports for the child (`(ghostel--spawn-native-process …)`).
   - *Emacs PTY*: `make-process :connection-type 'pty` runs `/bin/sh -c "stty …; exec <shell>"`,
     so `process-id` is the shell's PID after `exec`.
   - ⇒ the `/proc/<ghostel--pid>/stat` anchor (field 8 = `tpgid`) is valid in both modes. Local
     only; remote/TRAMP buffers spawn through Emacs machinery and the PID may be remote — see Q7.
2. **`ghostel-command-start-functions` / `ghostel-command-finish-functions` exist** — native,
   event-driven hooks (ghostel-shell.el:153-185):
   - start: called with the buffer when the shell emits an **OSC 133 C** marker (fires from the
     shell's *preexec* hook **just before** the user's command runs).
   - finish: called with `(buffer exit-status)` on the **OSC 133 D** marker (command finished /
     prompt redraw).
   - Both require shell integration; ghostel auto-injects it for bash/zsh/fish/nushell when
     `ghostel-shell-integration` is non-nil — it is the package default **and** firemacs sets it
     explicitly (ghostfire.el:53). Errors in hooks are demoted via `with-demoted-errors`.
   - Hooks fire **synchronously from the terminal parser** — the docstring recommends deferring
     non-trivial work with `run-at-time`.
   - `ghostel-exec` sessions (broot) get **no** shell integration ⇒ no C/D markers (moot — D5
     filter excludes them anyway).
   - Note: at the C marker the child has not necessarily been forked yet (preexec precedes
     execution), so the fg read must be deferred briefly (see implementation).
3. **Ghostel has its own buffer-name machinery** (`ghostel-buffer-name-function`,
   `ghostel--set-title`, ghostel.el:384-399, 3432-3457):
   - `ghostel-title` (buffer-local, OSC 0/2) is tracked; `ghostel-buffer-name-function` is called
     on title changes AND on OSC 7 `cd` reports (ghostel.el:3616-3618).
   - **`ghostel--rename-managed` declines after a manual rename**: it only renames while
     `ghostel--managed-buffer-name` is nil or equals the current buffer name (ghostel.el:3432-3440).
     Firemacs' existing post-spawn rename already puts the buffer in the "manually renamed" state,
     so ghostel's title tracking will never fight us — **and** we must not set
     `ghostel-buffer-name-function` globally or ghostel would *try* to claim names on title/cd
     events (it would just decline, but there is no need to enable it).
   - Buffer reuse by `ghostel`/`ghostel-N` matches on `ghostel-identity` (buffer-local, untouched
     by renames) — renaming does not break instance reuse or bookmarks/desktop identity lookups.
4. **Exit lifecycle**: `ghostel-kill-buffer-on-exit` defaults to `t` (buffer is killed when the
   terminal process exits); `ghostel-exit-functions` (buffer, exit-string) is available if we ever
   need a cleanup hook. Mode line shows the OSC title independently
   (`ghostel-buffer-identification-format`, `%t`) — not affected by our naming.

## Current naming plumbing

| Need | Existing code |
|---|---|
| Index reuse (lowest free) | `my/ghostel-next-available` — scans buffer names for a `"<N><sep>"` prefix (ghostfire.el:110) |
| Spawn + name (M-t) | `my/ghostel-new` → `(rename-buffer (format "%d<sep>%d" index pid))` (ghostfire.el:122-159) |
| Spawn + name (consult, by typed index) | `my/ghostel-spawn-at-index` → same rename (ghostfire.el:250-259) |
| Anchor PID (buffer-local) | `ghostel--pid` — the terminal child PID (recon #1) |
| Command events | `ghostel-command-start-functions` / `ghostel-command-finish-functions` (recon #2) |
| Mode guard | `(derived-mode-p 'ghostel-mode)`; broot sessions are `broot-mode` *derived from* `ghostel-mode` |
| Tab label | MRU-tabs `my/ct--tab-label` shows `buffer-name` verbatim — **no MRU-tabs change needed** |

## D-series decisions

### D1 — What to show at rest (at the shell prompt, no job running)
**Chosen: the shell's own name** (`bash`, `zsh`, `fish`, …). The label flips to the foreground
job's leader while one runs (`htop`, `vim`, `ssh`, …) and back to the shell when it exits.
Rejected: only-label-jobs (barer tab, less informative), always-the-shell (feature would be
invisible).

### D2 — Wrapper processes (`sudo vim`, `ssh host`, `env FOO=1 cmd`)
**Chosen: show the foreground leader's name as-is** — `sudo`, `ssh`, `env`. Predictable, honest,
zero heuristics. Unwrapping (`sudo vim` → `vim`) and full-cmdline labels are explicitly out of
scope (a tab is a few characters; cmdline is the domain of a tooltip/preview, not the name).

### D3 — Where does the PID go?
**Chosen: buffer-local `ghostel--pid` only** — no toggle to restore PID names, no PID kept in the
name. `broot/broot.el:148` and debugging already read `(buffer-local-value 'ghostel--pid buf)`
and are unaffected by renaming.

### D4 — Refresh mechanism — **REVISED after Phase 0: event-driven, no polling needed**
Research (prior draft) showed there is **no kernel event** an out-of-session process can get for
foreground-group changes (tcgetpgrp is session-bound; inotify cannot watch /proc; pidfd is
exit-only; even VTE must poll/crawl /proc). Phase 0 recon then found that **ghostel already
provides the event layer**: the OSC 133 C/D markers emitted by its own injected shell integration.

**Chosen: hook the command lifecycle events, with an optional poll as fallback only.**
1. **`ghostel-command-start-functions`** (OSC 133 C, fires before the command runs): schedule a
   one-shot `run-at-time` (~0.1 s) to read the fg process and rename. No timer keeps running —
   the read is a single cheap `/proc` lookup per command start.
2. **`ghostel-command-finish-functions`** (OSC 133 D, fires when the command ends / prompt
   redraws): read the fg process and rename immediately (fg is back to the shell).
3. **At spawn** (`my/ghostel-new`, `my/ghostel-spawn-at-index`): name with the shell's name right
   away (same read chain; at spawn fg == shell).
4. **Optional polling fallback** (defcustom, default **off**): for shells with no OSC 133
   integration (plain `/bin/sh`, TRAMP terminals with `ghostel-tramp-shell-integration` nil) the
   C/D hooks never fire; enabling the interval makes a visible-only poll cover those. Kept as an
   option, not the mechanism.

Both hooks fire synchronously in the terminal parser, so all work is deferred via `run-at-time`
(per the hook docstrings) and guarded by the D5 buffer filter.

### D5 — Which buffers do we rename? (broot must be left alone)
**Chosen: only buffers we "own"** — name matches `^[0-9]+<sep>` (the index prefix we wrote).
- Broot sessions (`broot-mode`, derived from `ghostel-mode`) are named `"broot"`, `"broot<2>"`,
  … by `my/broot--open` and must **not** be swept by a `ghostel-mode`-wide refresh — broot's own
  toggle logic (`my/broot-default-directory` and friends) relies on those names. The index-prefix
  filter excludes them naturally (and broot gets no OSC 133 markers anyway, recon #2).
- The C/D hook handlers run in whatever ghostel buffer emitted the marker; each handler starts by
  returning unless the buffer name matches the managed prefix.

### D6 — Format & separator
Keep today's literal separator (the glyph between index and PID, and the exact spacing) as a
single named constant so the spawn renames, the prefix scan, and the refresh all share it:

```elisp
(defconst my/ghostel-name-sep "  "   ; byte-identical to the current "%d  %d" middle
  "Separator between the index and the label in managed ghostel buffer names.")
```

New name: `(format "%d%s%s" index my/ghostel-name-sep label)`.
Update `my/ghostel-next-available` (and the two rename sites) to use the constant.

### D7 — Login-shell dash & comm sanity
Linux `comm` is short (historically ≤ 15 chars) and contains no `/` or whitespace — safe in a
buffer name. Login shells report `-bash`; strip one leading `-` so the tab reads `bash`. Strip
any control characters defensively. (macOS login-wrap and non-Linux: the `/proc` read returns nil
and the name falls back to spawn-time; see Q7.)

## Proposed implementation (ghostfire.el, new section after "Indexed Terminal Spawning")

```elisp
;; ── Live process-name buffer labels ─────────────────────────────────────────
(defcustom my/ghostel-name-read-delay 0.1
  "Seconds to wait after an OSC 133 command-start marker before reading the
foreground process.  The marker fires in preexec, before the child exists."
  :type 'number
  :group 'ghostel)

(defcustom my/ghostel-name-fallback-poll-interval nil
  "Optional fallback polling interval (seconds) for shells without OSC 133
integration (plain sh, remote TRAMP without tramp shell integration).
nil (default) disables the poll; the OSC 133 hooks handle integrated shells."
  :type '(choice (const :tag "Off" nil) number)
  :group 'ghostel)

(defconst my/ghostel-name-sep "  "
  "Separator between the index and the label in managed ghostel buffer names.")

(defun my/ghostel--anchor-pid (&optional buffer)
  "Return the anchor process PID (the terminal child, shell or exec'd program)."
  (and buffer (buffer-local-value 'ghostel--pid buffer)))

(defun my/ghostel--read-comm (pid)
  "Return the comm of PID from /proc, or nil."
  (let ((f (format "/proc/%s/comm" pid)))
    (when (and pid (file-readable-p f))
      (with-temp-buffer
        (insert-file-contents f)
        (string-trim (buffer-string))))))

(defun my/ghostel--tpgid (pid)
  "Foreground process-group id of PID's controlling terminal (Linux).
Reads field 8 of /proc/PID/stat; comm may contain parens/spaces, so parse
everything after the LAST ')' and take the 6th token
(state ppid pgrp sess tty tpgid)."
  (let ((f (format "/proc/%s/stat" pid)))
    (when (and pid (file-readable-p f))
      (with-temp-buffer
        (insert-file-contents f)
        (let* ((s (buffer-string))
               (after (and s (string-match ")" s)
                           (substring s (1+ (match-end 0)))))
               (tok (and after (nth 5 (split-string after)))))
          (and tok (string-to-number tok)))))))

(defun my/ghostel--fg-name (&optional buffer)
  "Name of the foreground process in BUFFER's terminal.
Chain: foreground group leader's comm → the anchor process's own comm (the
shell at rest) → nil.  Strips a leading '-' (login-shell comm convention)."
  (let* ((anchor (my/ghostel--anchor-pid buffer))
         (fg     (and anchor (my/ghostel--tpgid anchor)))
         (name   (or (and fg (my/ghostel--read-comm fg))
                     (my/ghostel--read-comm anchor))))
    (when name
      (string-trim-left name "-"))))

(defun my/ghostel--managed-name-p (name)
  "Non-nil when NAME belongs to a buffer this feature manages (index prefix)."
  (string-match-p (rx bos (+ digit) (literal my/ghostel-name-sep)) name))

(defun my/ghostel--buffer-index (buffer)
  "Numeric index parsed from BUFFER's name."
  (string-to-number (buffer-name buffer)))

(defun my/ghostel--apply-name (buffer name)
  "Rename managed BUFFER to \"INDEX<sep>NAME\" when the label changed."
  (when (and buffer (buffer-live-p buffer)
             (my/ghostel--managed-name-p (buffer-name buffer)))
    (let ((want (format "%d%s%s" (my/ghostel--buffer-index buffer)
                        my/ghostel-name-sep name)))
      (unless (equal want (buffer-name buffer))
        (rename-buffer want)))))

(defun my/ghostel--refresh-name (buffer)
  "Read BUFFER's foreground process and rename if it changed.  Deferred-safe."
  (when (and buffer (buffer-live-p buffer)
             (my/ghostel--managed-name-p (buffer-name buffer)))
    (when-let ((name (my/ghostel--fg-name buffer)))
      (my/ghostel--apply-name buffer name))))

(defun my/ghostel--on-command-start (buffer)
  "OSC 133 C: the shell is about to run a command.
Defer the fg read briefly — preexec fires before the child is forked."
  (run-at-time my/ghostel-name-read-delay nil
               (lambda () (my/ghostel--refresh-name buffer))))

(defun my/ghostel--on-command-finish (buffer _exit-status)
  "OSC 133 D: the command ended (or a prompt redraw).  fg is the shell again."
  (run-at-time 0 nil (lambda () (my/ghostel--refresh-name buffer))))

(add-hook 'ghostel-command-start-functions  #'my/ghostel--on-command-start)
(add-hook 'ghostel-command-finish-functions #'my/ghostel--on-command-finish)

(defun my/ghostel-rename-all ()
  "Interactive: refresh every managed ghostel buffer's label now."
  (interactive)
  (dolist (buf (my/ghostel-buffer-list))
    (my/ghostel--refresh-name buf)))
```

Optional fallback poll (only if `my/ghostel-name-fallback-poll-interval` is non-nil), same
visible-only scan as the earlier draft but default-off:

```elisp
(defun my/ghostel--fallback-poll ()
  (when my/ghostel-name-fallback-poll-interval
    (dolist (buf (my/ghostel-buffer-list))
      (when (and (my/ghostel--managed-name-p (buffer-name buf))
                 (get-buffer-window buf 'visible))
        (my/ghostel--refresh-name buf)))))

;; Q6: timer started ONCE at load from the defcustom value — no :set restart.
(when my/ghostel-name-fallback-poll-interval
  (run-with-timer my/ghostel-name-fallback-poll-interval
                  my/ghostel-name-fallback-poll-interval
                  #'my/ghostel--fallback-poll))
```

Then the two spawn sites change from `(rename-buffer (format "%d  %d" index pid))` to a shared
call that names with the *initial* foreground name (at spawn that is the shell, so the first label
is right without waiting for a tick), e.g. in `my/ghostel-new` / `my/ghostel-spawn-at-index`:

```elisp
;; after the process is live (post-spawn rename — never bind ghostel-buffer-name):
(let ((label (or (my/ghostel--fg-name) (number-to-string pid))))
  (rename-buffer (format "%d%s%s" index my/ghostel-name-sep label)))
```

(`my/ghostel-next-available` and any other prefix scan switch to `my/ghostel-name-sep` so the
index logic is unaffected by the label change.)

Notes:
- We deliberately do **not** touch `ghostel-buffer-name-function` / `ghostel--managed-buffer-name`:
  after our post-spawn rename ghostel's own title tracking declines to rename (recon #3), so there
  is no fight and no global state to undo.
- All work is deferred (`run-at-time`) because the C/D hooks run synchronously in the parser.

## Edge cases & risks

- **C marker precedes the fork** — the deferred read (default 0.1 s) handles this. Very fast
  commands (`ls`) may finish before the read: the label briefly stays/returns to the shell, no
  flicker (rename-on-change only).
- **Pipelined jobs with a dead leader** (`cat <file> | less`): `tpgid` points at the dead leader
  `cat`; the comm read fails and the fallback shows the shell — `less` is not displayed. VTE had
  the same gap and solved it with a group-member scan. Accept for v1 (see Q3), revisit if it
  bothers you.
- **Manual `M-x rename-buffer`** of a managed terminal gets overwritten by the next event. Accept
  (they're "ours"), or add a per-buffer opt-out flag (Q5).
- **jumpring** stores non-file jump targets by buffer name (jumpring.el:80); after a rename a
  stored `C-o` entry may dangle. Jumps land in terminals rarely; verify no error spam (Q4).
- **MRU-tabs** renders `buffer-name` per redisplay — labels update automatically; the 7-char
  statuscolumn and group icons are unaffected.
- **Daemon + emacsclient**: hooks/timers run daemon-side, which is where the ghostel buffers
  live — fine.
- **Non-Linux / remote**: `/proc` reads return nil (macOS, or TRAMP where `ghostel--pid` is not a
  local pid) → the label falls back to spawn-time (shell name) and stays; OSC 133 hooks still fire
  but read nothing. Acceptable; documented. Optional: gate reads with `(file-readable-p …)` —
  already done.
- **`ghostel-kill-buffer-on-exit` (default t)** kills the buffer when the terminal process exits —
  no stale-name cleanup needed; `ghostel-exit-functions` exists if we ever want one.

## Test checklist (manual)

1. `M-t` spawn → buffer/tab reads `1 bash` (or your shell); index prefix intact.
2. Run `htop` → becomes `1 htop` ~0.1 s after the command starts; quit → back to `1 bash`
   (event-driven; confirm **no** periodic renames happen while sitting at the prompt).
3. Run `vim`/`nvim`, then `ssh host`, then `sudo vim` → labels `vim`, `ssh`, `sudo` (D2).
4. `M-i` (consult-buffer): Ghostel section shows live names; typing a new index spawns without
   collisions; killing a terminal frees its index.
5. MRU-tabs: Ghostel-group tabs track renames with no flicker; no churn when nothing changes.
6. Broot (`M-e`): session buffer stays `"broot"`/`"broot<2>"`; ghostel--pid / dir-sync still
   works (D5 filter).
7. `C-o`/`C-i` after a rename: no errors (may silently skip stale entries).
8. `M-x my/ghostel-rename-all` refreshes everything immediately.
9. Optional poll: set `my/ghostel-name-fallback-poll-interval` to `2.0` → a `sh`/non-integrated
   shell's label tracks; back to `nil` → event-only again.
10. Emacs daemon + emacsclient: labels still track in client frames.
11. Login shell shows `bash` not `-bash` (D7).
12. `*Messages*` clean — no errors from hook handlers during fast command sequences.

## Implementation notes (2026-07 — applied to ghostel/ghostfire.el)

- New tail section "Live process-name buffer labels": `my/ghostel-name-read-delay` (0.1 s, Q1),
  `my/ghostel-name-fallback-poll-interval` (nil, Q2/Q6), the `/proc` readers, the rename helpers,
  `my/ghostel-rename-all`, the OSC 133 C/D hook handlers, and the optional poll + timer.
- `my/ghostel-name-sep` is built as `" " + (char-to-string #xE0B9) + " "` — byte-identical to the
  legacy `"%d  %d"` literal (verified via hexdump: `20 ee 82 b9 20`) while keeping the source
  ASCII (the private-use glyph cannot round-trip through text edits reliably). The three legacy
  glyph-bearing lines were therefore left untouched.
- The spawn functions (`my/ghostel-new`, `my/ghostel-spawn-at-index`) immediately name the fresh
  buffer `"<index><sep>syncing..."` — **the PID is never written to a buffer name** (see fix log
  below). The relabel machinery then swaps the placeholder for the real process name, and the OSC
  133 command-lifecycle hooks keep it current afterwards.
- OSC hooks (`ghostel-command-start-functions` / `-finish-functions`) and `ghostel-mode-hook` are
  attached inside `with-eval-after-load 'ghostel` (the package is deferred; the hook variables live
  in `ghostel-shell.el`, which ghostel.el requires eagerly).

### Fix log — first-spawn race (found in testing)

Symptom: the FIRST terminal of a fresh daemon (spawned by `launch-firemacs`:
`emacsclient -nw --eval "(my/ghostel-new)"`, shared.nix) kept the transient `"1 <PID>"` name until
a later event (e.g. spawning the second tab) relabeled it.

Cause: the original spawn relabel was a single 0 s `run-at-time` fired from `ghostel-mode-hook`.
On the first-ever spawn the native child / module is still cold-starting, so the `/proc` reads
returned nothing at that instant and the relabel gave up permanently — nothing re-triggered until
the shell's first OSC 133 event.

Fix:
- `my/ghostel--refresh-name` now returns the label (or nil), so callers can distinguish
  "relabeled / already correct" from "not readable yet".
- New `my/ghostel--schedule-relabel` retries with backoff (first try at 0.05 s, +0.1 s per retry,
  up to 10 tries, ~1.4 s total) and stops as soon as a label is read.
- `my/ghostel--on-mode-activate` (ghostel-mode-hook) uses the retrying scheduler — covers every
  terminal-creation path — and `my/ghostel-new` additionally schedules a relabel explicitly right
  after its own rename, so the `launch-firemacs` first tab is relabeled deterministically.

Regression checks passed: byte-compile clean; broot buffers still untouched (index-prefix filter);
label flips to the shell name shortly after spawn and tracks foreground jobs thereafter.

### Fix log — PID labels removed entirely ("syncing..." placeholder)

Symptom/request: no PID may ever be visible in a ghostel buffer name — not even for a split
second. A freshly spawned terminal should show only `"<index><sep>syncing..."` or the actual
process name.

Decision (D8): remove the PID from both spawning functions completely.

Implementation:
- New constant `my/ghostel-name-syncing-label` = `"syncing..."` (defined above the spawn
  functions so the byte-compiler sees it before first use).
- `my/ghostel-new` (ghostfire.el) — after `(ghostel t)` it renames unconditionally to
  `(my/ghostel--name index my/ghostel-name-syncing-label)` (uniquify `t`); the old process-live
  `when-let*` gate and the `(format "%d<sep>%d" index pid)` rename are gone. The retrying
  `my/ghostel--schedule-relabel` then swaps the placeholder for the real name.
- `my/ghostel-spawn-at-index` (consult-buffer numeric-spawn path) — identical treatment, plus an
  explicit `my/ghostel--schedule-relabel` call for parity with `my/ghostel-new` (previously it
  relied only on the mode hook).
- The two legacy glyph-bearing PID renames were replaced byte-exactly via a Python pass
  (`chr(0xE0B9)`) — the PUA glyph cannot be matched through ordinary text edits.

Behavior: users see `1 syncing...` → `1 bash` (or the running job's name); on systems where the
name can never be read (macOS / remote TRAMP), the tab stays at `1 syncing...`. Broot is
unaffected (never PID-named; excluded by the index-prefix filter). Byte-compile clean; remaining
warnings are pre-existing references to external package internals.

## Q&A — resolved decisions (all answered 2026-07)

| # | Question | Decision |
|---|---|---|
| Q1 | `my/ghostel-name-read-delay` default | **0.1 s** |
| Q2 | Fallback poll default | **Off** (OSC 133 hooks cover bash/zsh/fish/nushell; others keep spawn-time labels) |
| Q3 | Dead-leader pipelines (`cat \| less`) | **Accept shell-name fallback for v1**; VTE-style group-member scan is a v2 candidate |
| Q4 | jumpring + renames | **Accept stale entries**; no jumpring change now |
| Q5 | Manual `rename-buffer` on a managed terminal | **Accept auto-managed** — next event renames it back; no freeze flag |
| Q6 | Fallback-poll timer lifecycle | **Restart required** — timer started once at load from the defcustom value; no `:set` restart |
| Q7 | macOS / remote TRAMP terminals | **Spawn-time labels only**; `/proc` reads return nil there; no `ps` fallback |
| Q8 | Backfill older terminals at load | **No load-time backfill** — `my/ghostel-rename-all` is manual; existing terminals update on their next command event |

Implementation consequences:
- `my/ghostel-name-fallback-poll-interval` defaults to `nil` (Q2); timer code runs once at load (Q6).
- No freeze flag, no jumpring patch, no `ps` fallback, no load-time sweep (Q3/Q4/Q5/Q7/Q8) in v1.
