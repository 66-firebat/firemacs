#!/usr/bin/env bash
#
# restart-emacs-gui.sh — stop the Emacs daemon and start a graphical Emacs.
#
# Run this from a STANDALONE terminal (e.g. a fresh Ghostty window/pane).
# Do NOT run it from inside Emacs — a ghostel/eat/vterm buffer or `M-x shell`
# sets INSIDE_EMACS, and killing the daemon would kill this script and its
# terminal too.  The script refuses in that case.
#
# NOTE: the daemon is killed without saving.  Any modified buffers in the
# daemon are lost.  Save your work first.
#
# Usage:
#   ./restart-emacs-gui.sh [--dry-run]
#
# Environment overrides:
#   GUI_EMACS   Emacs binary to launch   (default: `emacs` on PATH)
#   GUI_LOG     log file                (default: ${TMPDIR:-/tmp}/emacs-gui.log)
#   GUI_ARGS    extra arguments         (default: empty)
#
# What it does:
#   1. asks the running `emacs --daemon` to exit, without confirmation prompts;
#   2. waits, then escalates to SIGTERM/SIGKILL if it stays alive;
#   3. launches a detached graphical `emacs` (never `-nw`).

set -u

say() { printf '%s\n' "$*"; }

DRY_RUN=0
case "${1:-}" in
  -n|--dry-run) DRY_RUN=1 ;;
  -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
  "") ;;
  *) say "unknown argument: $1 (try --help)"; exit 2 ;;
esac

# --- refuse to run from inside Emacs -----------------------------------------
if [ -n "${INSIDE_EMACS:-}" ]; then
  say "error: INSIDE_EMACS=$INSIDE_EMACS — this shell is inside Emacs."
  say "       Killing the daemon would also kill this script and its terminal."
  say "       Run this script from a standalone terminal instead."
  exit 1
fi

GUI_EMACS="${GUI_EMACS:-$(command -v emacs 2>/dev/null || true)}"
if [ -z "$GUI_EMACS" ] || [ ! -x "$GUI_EMACS" ]; then
  say "error: cannot find an executable emacs (set GUI_EMACS=/path/to/emacs)."
  exit 1
fi
GUI_LOG="${GUI_LOG:-${TMPDIR:-/tmp}/emacs-gui.log}"
# The config lives in ~/.config/emacs but user-emacs-directory resolves to
# ~/.emacs.d (which exists and has no init.el), so a plain `emacs` starts with
# the default config.  Load it explicitly, exactly like the daemon does.
GUI_INIT="${GUI_INIT:-$HOME/.config/emacs/init.el}"
if [ ! -f "$GUI_INIT" ]; then
  say "warning: init file $GUI_INIT not found — Emacs will use its default configuration."
fi

# --- helpers -----------------------------------------------------------------
# PIDs of `emacs --daemon` processes.  Matched on the process command line
# rather than by name so this script can't match itself.
daemon_pids() {
  local p
  for p in $(pgrep -x emacs 2>/dev/null || true); do
    if tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q -- '--daemon'; then
      printf '%s\n' "$p"
    fi
  done
}

wait_until_gone() {
  local _ pids
  for _ in $(seq 1 40); do
    pids=$(daemon_pids)
    [ -z "$pids" ] && return 0
    sleep 0.25
  done
  return 1
}

# --- 1. stop the daemon ------------------------------------------------------
if [ -n "$(daemon_pids)" ]; then
  say "Emacs daemon PIDs: $(daemon_pids | tr '\n' ' ')"
  if [ "$DRY_RUN" -eq 1 ]; then
    say "[dry-run] would stop the daemon here."
  else
    # Graceful exit, bypassing the kill-emacs confirmation prompts.
    if command -v emacsclient >/dev/null 2>&1; then
      timeout 10 emacsclient --eval \
        '(let ((kill-emacs-query-functions nil)) (kill-emacs))' >/dev/null 2>&1 || true
    fi
    if ! wait_until_gone; then
      say "daemon still alive; sending SIGTERM"
      for p in $(daemon_pids); do kill -TERM "$p" 2>/dev/null || true; done
      if ! wait_until_gone; then
        say "daemon still alive; sending SIGKILL"
        for p in $(daemon_pids); do kill -KILL "$p" 2>/dev/null || true; done
        wait_until_gone || say "warning: some daemon PIDs may remain"
      fi
    fi
    say "daemon stopped."
  fi
else
  say "no Emacs daemon running."
fi

# --- 2. start a graphical Emacs ---------------------------------------------
if [ "$DRY_RUN" -eq 1 ]; then
  say "[dry-run] would start: $GUI_EMACS -l $GUI_INIT ${GUI_ARGS:-}"
  say "[dry-run] DISPLAY=${DISPLAY:-<unset>} WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-<unset>}"
  exit 0
fi

if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
  say "warning: DISPLAY and WAYLAND_DISPLAY are both unset — GUI Emacs may not open a window."
fi

say "starting GUI Emacs: $GUI_EMACS -l $GUI_INIT (log: $GUI_LOG)"
# setsid + nohup so it outlives this terminal; </dev/null so it never reads here.
# shellcheck disable=SC2086
setsid nohup "$GUI_EMACS" -l "$GUI_INIT" ${GUI_ARGS:-} >"$GUI_LOG" 2>&1 </dev/null &
disown 2>/dev/null || true

sleep 2
if pgrep -x emacs >/dev/null 2>&1; then
  say "GUI Emacs launched (PIDs: $(pgrep -x emacs | tr '\n' ' '))."
else
  say "Emacs does not appear to be running. Last lines of $GUI_LOG:"
  tail -n 20 "$GUI_LOG" 2>/dev/null || true
  exit 1
fi
