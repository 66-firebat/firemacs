# PATCH — broot sessions own ESC (keep Evil insert state)

Status: **implemented** (code in `broot/broot.el`).

## Problem

Broot is itself modal: `s` opens a search in broot's input mode, and ESC
returns to broot's command mode. A broot session is a Ghostel terminal in
Evil insert state, so ordinary keys reach broot through the PTY — but ESC
does not. `evil-ghostel`'s insert-state `<escape>` binding
(`evil-ghostel--escape`) defaults to `auto` routing, which forwards ESC to
the terminal only when `ghostel-alt-screen-p` is true. Broot does not trip
that alternatescreen heuristic, so ESC ran Evil's binding and switched the
Emacs buffer to Evil normal state without ever reaching broot.

## Fix

`broot/broot.el`, new buffer setup in `broot-mode-hook`:

```elisp
(defun my/broot--route-escape-to-terminal ()
  "Route insert-state ESC to the broot process instead of Evil."
  (when (bound-and-true-p evil-ghostel-mode)
    (setq-local evil-ghostel--escape-mode 'terminal)))

(add-hook 'broot-mode-hook #'my/broot--route-escape-to-terminal)
```

- `evil-ghostel--escape-mode` is evil-ghostel's documented per-buffer routing
  switch (`auto` / `terminal` / `evil`), so this is the intended extension
  point rather than advice.
- `broot-mode-hook` runs after `ghostel-mode-hook`, where `evil-ghostel-mode`
  initialises the routing from the global `evil-ghostel-escape`; the override
  therefore sticks. The buffer stays in insert state and ESC is sent to the
  PTY on every press.
- Scoped to `broot-mode`: plain Ghostel terminals keep `auto`.

### Escape hatches preserved

- `C-c <escape>` still switches to Evil normal state once (e.g. to reach the
  global `S` → `my/consult-ripgrep-with-jump`), without changing the routing.
- `C-c C-r` still cycles the routing via
  `evil-ghostel-toggle-send-escape`.

## Validation

- Batch tests against the real `evil` / `ghostel` / `evil-ghostel` packages:
  - broot buffer → `evil-ghostel--escape-mode` = `terminal`; a plain Ghostel
    buffer stays `auto`.
  - With `evil-mode` on, a broot buffer starts in `insert` state and `s` is
    `ghostel--self-insert` (delivered to broot), not the global normal-state
    consult binding.
  - Calling `evil-ghostel--escape` in a broot buffer sends `("escape" "")` to
    the terminal and does **not** enter normal state.
- `broot/broot.el` byte-compiles clean (only the pre-existing `when-let`
  obsolescence warning on Emacs 31.1).
