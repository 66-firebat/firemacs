# PATCH — `my/ghostel-cd-from-broot`: M-t reuses a terminal instead of spawning one

Status: **implemented** in `ghostel/ghostfire.el` (dispatch alist entry
`broot-mode` → `my/ghostel-cd-from-broot`); `broot/broot.el` header updated.

Supersedes `patches/ghostel-new-from-broot.md`.

## Goal

Pressing `M-t` inside a broot session should stop creating a new terminal
buffer on every jump.  Instead it should:

1. read broot's live cwd (`my/broot-sync-default-directory`, the on-demand
   procfs read used by `my/consult-ripgrep-with-jump`),
2. send `cd <dir> && clear` to the **most recently used plain Ghostel
   terminal**,
3. switch to that terminal, and
4. kill the broot buffer that was being used.

Net effect: the terminal count stays flat, and the broot buffer disappears
instead of accumulating.

## Implementation

### MRU lookup (ghostfire.el)

`buffer-list` is already ordered most-recently-used first, so the first
matching buffer is the MRU terminal.  Broot sessions are excluded because
`broot-mode` derives from `ghostel-mode`.  Dead terminals are skipped.

```elisp
(defun my/ghostel--mru-terminal-buffer ()
  (seq-find (lambda (buf)
              (with-current-buffer buf
                (and (derived-mode-p 'ghostel-mode)
                     (not (derived-mode-p 'broot-mode))
                     (bound-and-true-p ghostel--process)
                     (process-live-p ghostel--process))))
            (buffer-list)))
```

### Handler (ghostfire.el)

```elisp
(defun my/ghostel-cd-from-broot ()
  (interactive)
  ;; dir = broot's live cwd, with warn + default-directory fallback
  ;; target = (my/ghostel--mru-terminal-buffer)
  ...
  (with-current-buffer target
    (ghostel-send-string
     (format "cd %s && clear\n" (shell-quote-argument dir))))
  (switch-to-buffer target)
  (kill-buffer broot-buf))
```

- `shell-quote-argument` handles spaces/quotes in directory names.
- `&& clear` matches `ghostfire-travel`'s convention: the shell moves, then
  the screen is cleared.
- The broot buffer is killed **after** switching away, so the window ends up
  on the terminal.
- `kill-buffer` on a broot session does not normally prompt:
  `ghostel-query-before-killing` defaults to `'auto`, which only asks while a
  shell command is running (OSC 133), and broot is not a shell.

### Fallback

When no plain terminal is open (the broot session is the only Ghostel
buffer), the handler spawns one with `my/ghostel-new` rooted at broot's cwd
and still kills the broot buffer.  This preserves the old "get me a shell
here" outcome on first use, while subsequent presses reuse that terminal.

### Unchanged

- `my/ghostel-new-dispatch` still routes every other buffer/mode to
  `my/ghostel-new` at `my/ghostel-working-dir`, and still spawns a new
  numbered terminal.
- Other broot sessions are left alive; only the session M-t was pressed in
  is killed.
- `M-z` (`my/zoxide-travel-dispatch`) behavior is untouched.

## Behavior table

| Context | Before | After |
|---------|--------|-------|
| M-t in a broot session, ≥1 plain terminal open | New numbered terminal at broot's cwd; broot buffer stays | `cd` MRU terminal to broot's cwd; switch to it; kill broot buffer |
| M-t in a broot session, no plain terminal | New numbered terminal at broot's cwd; broot buffer stays | Spawn terminal at broot's cwd; kill broot buffer |
| M-t in a plain terminal | New numbered terminal at live cwd | Unchanged |
| M-t anywhere else | New numbered terminal at `default-directory` | Unchanged |
| broot cwd unreadable | New terminal at `default-directory` | Warn, then cd/spawn at `default-directory` |

## Caveats

- If the MRU terminal is running a foreground program (e.g. `nvim`), the
  `cd ...` text goes to that program, not a shell prompt.  This is the same
  caveat as `ghostfire-travel` (`M-z`); no guard is added here.
- "Most recently used" is `buffer-list` selection order.  A terminal merely
  visible in another window without having been selected may not be first.

## Validation

- `check-parens` / byte-compile `ghostel/ghostfire.el` and `broot/broot.el`.
- Live QA: open a terminal, open broot, navigate deep, press `M-t` → screen
  lands in the existing numbered terminal, `pwd` shows broot's cwd, broot
  buffer is gone.  Repeat to confirm the terminal count does not grow.
- With no terminal open: open broot first, press `M-t` → one terminal is
  created at broot's cwd and broot is closed.
