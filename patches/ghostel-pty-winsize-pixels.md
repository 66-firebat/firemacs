# ghostel `fix/pty-winsize-pixels` — install a non-default branch

**Status:** RESEARCH COMPLETE — actionable; human action required (delete tarball, build native module)
**Date:** 2026-09-13
**Scope:** Emacs 30.2, NixOS + home-manager, plain `package.el` + MELPA,
`package-user-dir` = `~/.emacs.d/elpa`.

Goal: run the GitHub branch
[`dakra/ghostel` `fix/pty-winsize-pixels`](https://github.com/dakra/ghostel/tree/fix/pty-winsize-pixels)
so broot's kitty-graphics image previews stop falling back to text.

---

## Findings

- The branch **exists and is unmerged**. Tip commit `c872539c20a05c3cfb322211728f25ef0a9f6fec`
  is exactly **1 commit ahead of `main`** (`9bf8c7a7f624eaba60d46b7b1123d29c39a2f4da`), 0 behind;
  no pull request exists for it. See the [branches API](https://api.github.com/repos/dakra/ghostel/branches)
  and the [compare page](https://github.com/dakra/ghostel/compare/main...fix/pty-winsize-pixels).
- The single commit is *"Report cell pixel dimensions in the native PTY window size"*
  (Daniel Kraus, 2026-09-13T19:43:26Z), and it exists to fix
  [issue #675](https://github.com/dakra/ghostel/issues/675). See the
  [commit API](https://api.github.com/repos/dakra/ghostel/commits/c872539c20a05c3cfb322211728f25ef0a9f6fec).
- **The fix is entirely in the Zig native module, not in Elisp.** The branch's
  `lisp/` tree is byte-for-byte the same as `main`. Installing only the Elisp from
  the branch does nothing; the native `.so` must be **compiled from the branch source**.
- The newest release is **v0.53.0 (2026-09-02)**, which predates the branch commit
  (2026-09-13) and does **not** contain the fix ([tags](https://api.github.com/repos/dakra/ghostel/tags),
  [releases](https://api.github.com/repos/dakra/ghostel/releases)). The prebuilt module
  that ghostel auto-downloads is therefore the *unfixed* one.
- Both the branch and the v0.53.0 release declare module version **`0.53.0`**
  (`src/version.zig`; `Version: 0.53.0` in `lisp/ghostel.el`; `ghostel--minimum-module-version`
  is `"0.53.0"`), so ghostel's version check **cannot tell the fixed module from the
  unfixed release binary**. Do not let `ghostel-download-module` / auto-install run.
- The repo is a **multi-file package** whose main file is `lisp/ghostel.el`
  (`Package-Requires: ((emacs "28.1") (compat "30.1.0.1"))`), not a root `ghostel.el`;
  `package-vc` needs `:lisp-dir "lisp"` on Emacs < 31.1.
- MELPA has **no end-user mechanism to install a branch**. Its recipe format has
  `:branch`/`:commit`, but those are maintainer-side build settings; the published
  `recipes/ghostel` has no `:branch`, so MELPA tracks the default branch only.
- The canonical Emacs-native way to get a non-default revision into `package-user-dir`
  is **`package-vc-install`** with a `(name . spec)` plist including `:branch`.
- On this machine the currently installed copy is the MELPA snapshot
  `~/.emacs.d/elpa/ghostel-20260902.1753` (module sidecar `0.53.0`); the repo's own
  `elpa/` directory is **not** the runtime `package-user-dir`.

### Local environment (verified)

| Item | Value |
|---|---|
| Emacs | 30.2 (`/run/current-system/sw/bin/emacs`) |
| `user-emacs-directory` | `~/.emacs.d/` (so init is loaded via `-l ~/.config/emacs/init.el`) |
| `package-user-dir` | `~/.emacs.d/elpa` (default) |
| `custom-file` | `~/.emacs.d/custom.el` — **real, writable** file (init.el line 481) |
| Installed ghostel | `~/.emacs.d/elpa/ghostel-20260902.1753`, `ghostel-module.so` + sidecar `0.53.0` |
| Config files | `~/.config/emacs/*.el` are read-only symlinks into the Nix store; edits go through this repo + `home-manager switch` |

---

## Branch diff summary

`git`-level: `main..fix/pty-winsize-pixels` = **1 commit, 7 files, +83 / −28**
([compare](https://github.com/dakra/ghostel/compare/main...fix/pty-winsize-pixels),
[full patch](https://github.com/dakra/ghostel/commit/c872539c20a05c3cfb322211728f25ef0a9f6fec.diff)):

| File | Change |
|---|---|
| `src/backend_types.zig` | **new** `WinSize { cols, rows, xpixel = 0, ypixel = 0 }` (+8) |
| `src/PosixPtyProcess.zig` | `Pty.resize` now fills `ws_xpixel`/`ws_ypixel` in `c.winsize` instead of hard-coding `0`, before `ioctl(TIOCSWINSZ)` (+11/−6) |
| `src/GhostelTerm.zig` | new `pty_size` field + `winSize()` (uses `terminal.width_px/height_px`); redraw resends resize when grid **or pixel** geometry changed (+27/−12) |
| `src/NativeProcess.zig`, `src/ConPtyProcess.zig` | plumb `WinSize` through the backends (ConPTY ignores pixel fields) |
| `CHANGELOG.md` | entry under Unreleased → Fixed (+4) |
| `test/ghostel-spawn-test.el` | new ERT test asserting `TIOCGWINSZ` returns pixel fields (+24) |

The core change:

```zig
// src/PosixPtyProcess.zig — before: ws_xpixel = 0, ws_ypixel = 0
const size = c.winsize{
    .ws_col = ws.cols, .ws_row = ws.rows,
    .ws_xpixel = ws.xpixel, .ws_ypixel = ws.ypixel,   // <-- fix
};
ioctl(self.primary_fd, c.TIOCSWINSZ, &size);
```

```zig
// src/GhostelTerm.zig
fn winSize(self: *Self) WinSize {
    return .{
        .cols   = self.terminal.cols,
        .rows   = self.terminal.rows,
        .xpixel = std.math.lossyCast(u16, self.terminal.width_px),
        .ypixel = std.math.lossyCast(u16, self.terminal.height_px),
    };
}
```

The CHANGELOG states the effect directly: *"The native PTY's window size
(`TIOCGWINSZ`) carries the cell pixel geometry, so image tools that size kitty
graphics from it (broot, ranger) no longer fall back to text rendering."*
([CHANGELOG](https://raw.githubusercontent.com/dakra/ghostel/fix/pty-winsize-pixels/CHANGELOG.md)).
The new test asserts `WS 24 80 720 552` (i.e. `80*9` by `24*23`) instead of zero
pixel fields ([test source](https://raw.githubusercontent.com/dakra/ghostel/fix/pty-winsize-pixels/test/ghostel-spawn-test.el)).

### Package metadata

- `lisp/ghostel.el` header: `Version: 0.53.0`, `Package-Requires: ((emacs "28.1") (compat "30.1.0.1"))`
  ([raw](https://raw.githubusercontent.com/dakra/ghostel/fix/pty-winsize-pixels/lisp/ghostel.el)).
- `src/version.zig`: `pub const version = "0.53.0"`; `build.zig` writes
  `ghostel-module.version` next to the binary and requires **exactly Zig 0.16.0**
  ([version.zig](https://raw.githubusercontent.com/dakra/ghostel/fix/pty-winsize-pixels/src/version.zig),
  [build.zig](https://raw.githubusercontent.com/dakra/ghostel/fix/pty-winsize-pixels/build.zig)).
- `lisp/ghostel-module-install.el` documents the `package-vc` layout explicitly:
  *"dev / `package-vc-install`: ghostel.el lives under `lisp/`, so the resource root is
  the parent of the Lisp directory"* — i.e. `ghostel-module-compile` works from a
  package-vc checkout ([raw](https://raw.githubusercontent.com/dakra/ghostel/fix/pty-winsize-pixels/lisp/ghostel-module-install.el)).
- The project's own docs list the supported install methods — MELPA, `use-package :vc`,
  `:load-path`, manual ([README.org Installation](https://raw.githubusercontent.com/dakra/ghostel/fix/pty-winsize-pixels/README.org),
  rendered at [dakra.github.io/ghostel/#installation](https://dakra.github.io/ghostel/#installation)).

### MELPA

- Recipe: `(ghostel :fetcher github :repo "dakra/ghostel" :files (:defaults "etc" "src" "vendor" "build.zig" "build.zig.zon" "symbols.map"))`
  — no `:branch`/`:commit` ([recipe](https://raw.githubusercontent.com/melpa/melpa/master/recipes/ghostel)).
- MELPA's recipe schema does support `:commit` and `:branch` ("must be specified when
  using a branch other than the default branch"), but these are build-recipe keys chosen
  by MELPA maintainers, not settings an installing user can supply at `package-install`
  time ([MELPA README recipe section](https://github.com/melpa/melpa/blob/master/README.md)).
  There is no per-user "install this branch" facility.

---

## How to install the branch

### Option A — `package-vc-install` (Emacs 29/30 built-in; recommended here)

`package-vc-install` accepts a `(NAME . SPEC)` package specification whose keys are
documented in the manual: `:url`, `:branch` (*"a string providing the revision of the
code to install"*), `:lisp-dir`, `:main-file`, `:vc-backend`, plus a `REV` argument
([Emacs manual — Fetching Package Sources](https://www.gnu.org/software/emacs/manual/html_node/emacs/Fetching-Package-Sources.html)).
For a non-archive spec it saves the spec into `package-vc-selected-packages` so
`package-vc-upgrade` keeps tracking the branch (`package-vc.el`, `package-vc--unpack`).
The manual notes VC packages *"behave just like any other package"* and can be deleted
with `package-delete` ([Emacs manual — Package Installation](https://www.gnu.org/software/emacs/manual/html_node/emacs/Package-Installation.html)).

**Step 1 — remove the MELPA tarball first.** A VC package installs to
`<package-user-dir>/ghostel` (no version suffix), while the tarball is
`<package-user-dir>/ghostel-<version>` (confirmed via `package-desc-full-name` in
`package.el` and the manual's `name-version` layout,
[Package Files](https://www.gnu.org/software/emacs/manual/html_node/emacs/Package-Files.html)).
The MELPA snapshot version `20260902.1753` sorts **higher** than the VC package's
`0.53.0`, so `package--get-activatable-pkg` returns the tarball and the branch is
ignored on the next startup — verified empirically:

```text
package-alist order (versions): ((20260902 1753) (0 53 0))
activatable version: (20260902 1753)
```

```elisp
;; in the running Emacs, or eval-buffer this block
(require 'package)
(package-initialize)
(package-delete (cadr (assq 'ghostel package-alist)) 'force)  ; delete ghostel-20260902.1753
```

**Step 2 — install the branch** (writes the checkout to `~/.emacs.d/elpa/ghostel`):

```elisp
(require 'package-vc)
(package-vc-install
 '(ghostel :url "https://github.com/dakra/ghostel"
           :branch "fix/pty-winsize-pixels"
           :lisp-dir "lisp"
           :vc-backend Git))
```

For a fully pinned install, pass the SHA as the optional `REV` argument instead of
relying on the branch pointer:

```elisp
(package-vc-install
 '(ghostel :url "https://github.com/dakra/ghostel"
           :branch "fix/pty-winsize-pixels"
           :lisp-dir "lisp"
           :vc-backend Git)
 "c872539c20a05c3cfb322211728f25ef0a9f6fec")
```

**Step 3 — build the native module from the branch** (requires Zig 0.16.0):

```elisp
;; ~/.emacs.d/elpa/ghostel is the resource root (parent of lisp/);
;; ghostel--resource-root detects this layout.  Compile from the checkout:
(require 'ghostel)
(ghostel-module-compile)          ; M-x ghostel-module-compile
;; writes ghostel-module.so + ghostel-module.version into the package dir
;; then restart Emacs so the new module is mapped
```

Optionally pin the module outside the package tree so package operations cannot clobber
it while Emacs has it mapped:

```elisp
(setq ghostel-module-directory (expand-file-name "ghostel-module/" "~/.emacs.d/"))
```

**Verify the module is the branch build** (not the release binary). One check is the
branch's own semantics: inside a ghostel buffer, query `TIOCGWINSZ` and confirm the
pixel fields are non-zero (the test uses `python3`):

```sh
python3 -c "import fcntl,struct,termios; print(struct.unpack('HHHH', fcntl.ioctl(0, termios.TIOCGWINSZ, b'\0'*8)))"
# expected shape (rows, cols, xpixel, ypixel), e.g. (24, 80, 720, 552), not (.., 0, 0)
```

### Option B — declarative `use-package :vc` (in the repo config)

The project's docs show `use-package` with `:vc` ([README.org](https://raw.githubusercontent.com/dakra/ghostel/fix/pty-winsize-pixels/README.org)):

```elisp
(use-package ghostel
  :vc (:url "https://github.com/dakra/ghostel"
       :branch "fix/pty-winsize-pixels"
       :lisp-dir "lisp"
       :rev :newest))        ; MUST override the default; see below
```

- `use-package`'s valid `:vc` keys are `(:url :branch :lisp-dir :main-file :vc-backend
  :rev :shell-command :make :ignored-files)` (`use-package-core.el`,
  `use-package-vc-valid-keywords`).
- **`:rev :newest` is required.** `use-package` defaults `:rev` to `:last-release`
  (unless `use-package-vc-prefer-newest` is non-nil). With `:last-release` the clone
  happens on the branch, then `package-vc--clone` runs `vc-retrieve-tag` to the last
  release revision — landing you back on v0.53.0 without the fix. Passing `:newest`
  (or an explicit rev) avoids this (`package-vc--clone`, `use-package-normalize--vc-arg`).
- **No `:ensure` conflict exists**: the config sets `use-package-always-ensure t`, but
  `use-package-handler/:ensure` computes `(ensure (and (not (plist-member rest :vc)) ensure))`,
  so any declaration carrying `:vc` suppresses `:ensure` automatically
  (`use-package-ensure.el`). It will not also pull the MELPA tarball.
- Because `~/.config/emacs/*.el` are read-only Nix-store symlinks, this edit must be made
  in this repo and applied with `home-manager switch`.

### Option C — Nix / `melpaBuild` (most reproducible for a NixOS dotfiles setup)

nixpkgs already ships a `ghostel` Emacs package built with `melpaBuild` that compiles
the native module with Zig and installs `ghostel-module${libExt}` plus the version
sidecar:

- `pkgs/applications/editors/emacs/elisp-packages/manual-packages/ghostel/package.nix`
  ([source at pinned rev](https://github.com/NixOS/nixpkgs/blob/0bb7ec54c8483066ec9d7720e780a5caa71f8612/pkgs/applications/editors/emacs/elisp-packages/manual-packages/ghostel/package.nix)).
  It currently pins `src.rev = eb806d158df4ff302aee68e91caf257f11d66320` (version
  `0.41.0-unstable-2026-07-06`) and builds with `zig_0_15`; its update script tracks
  `--version=branch=main`.
- `melpaBuild` uses MELPA's `package-build` and honours a `files` list; `trivialBuild`
  is the simpler byte-compile-`*.el` builder
  ([melpa.nix](https://github.com/NixOS/nixpkgs/blob/0bb7ec54c8483066ec9d7720e780a5caa71f8612/pkgs/applications/editors/emacs/build-support/melpa.nix),
  [trivial.nix](https://github.com/NixOS/nixpkgs/blob/0bb7ec54c8483066ec9d7720e780a5caa71f8612/pkgs/applications/editors/emacs/build-support/trivial.nix)).
- The pinned nixpkgs already provides `zig_0_16` and sets `zig = zig_0_16`
  ([all-packages.nix](https://github.com/NixOS/nixpkgs/blob/0bb7ec54c8483066ec9d7720e780a5caa71f8612/pkgs/top-level/all-packages.nix)).

To use the branch reproducibly, override that derivation: set
`src.rev = "c872539c20a05c3cfb322211728f25ef0a9f6fec"`, switch `zig = zig_0_16`, and
regenerate the `zig.fetchDeps` hash, then expose it through
`emacsPackagesFor` / `emacsWithPackages`. This is the only route that pins the Zig
source *and* the built module by hash. Trade-off: the current config uses
`package.el` + MELPA and home-manager-symlinked Elisp, not a wrapped
`emacsWithPackages`; adopting it is a larger config change and bypasses
`package-user-dir` entirely.

---

## Gotchas / human intervention needed

1. **The fix is in the native module — an Elisp-only install is useless.**
   `package-vc`/MELPA only manage `.el` files; you must run `ghostel-module-compile`
   from the branch checkout. Requires **exactly Zig 0.16.0**
   ([README.org](https://raw.githubusercontent.com/dakra/ghostel/fix/pty-winsize-pixels/README.org));
   other versions fail `build.zig`'s `@compileError`. No Zig is currently declared in
   `nixos-dotfiles` — add `zig` (the pinned nixpkgs default is 0.16.0) or use
   `nix shell nixpkgs#zig`.
2. **Delete the MELPA tarball** `~/.emacs.d/elpa/ghostel-20260902.1753`, or its higher
   snapshot version (`20260902.1753` > `0.53.0`) will be the activated package at the
   next startup. Verified with `package--get-activatable-pkg`. This is the single most
   likely way the branch silently fails to take effect.
3. **Do not let the module auto-download.** `ghostel--minimum-module-version` is
   `"0.53.0"` and the release binary is also `0.53.0`, so the loader accepts the
   unfixed release module. Set `ghostel-module-auto-install` to `'compile` (or `nil`)
   and build from the branch explicitly.
4. **`use-package :vc` defaults to `:last-release`.** Always add `:rev :newest` (or an
   explicit SHA), otherwise the branch is cloned and then reset to the v0.53.0 release
   (`package-vc--clone`).
5. **Confusing version numbers:** `main`'s tip (`9bf8c7a7`, author-dated 2026-08-17)
   is topologically *after* the v0.53.0 release (`2bea18f3`, 2026-09-02), and the branch
   is based on that `main` tip. The branch therefore already includes v0.53.0; its only
   unique commit is `c872539`.
6. **Branch name with a slash is harmless for paths.** `package-vc` names the checkout
   `<package-user-dir>/ghostel` (VC packages get no version suffix), so
   `fix/pty-winsize-pixels` is only ever a Git ref passed to `vc-clone`; it does not
   appear in a directory name.
7. **Autoloads/byte-compilation are handled by `package-vc--unpack-1`** (autoload
   generation, `package--compile`, selected-packages bookkeeping). Only the Zig module
   build is outside its scope.
8. **`custom-file` is writable here, so `package-vc-install` can persist its spec.**
   `custom-file` is `~/.emacs.d/custom.el` (init.el line 481, and `user-emacs-directory`
   is `~/.emacs.d`), a real file — *not* the read-only Nix-store `custom.el` symlink
   under `~/.config/emacs`. The spec save will succeed.
9. **Editing the config is a separate, Nix-mediated action.** Config `.el` files are
   read-only store symlinks; changing `ghostel/ghostfire.el` / `init.el` requires editing
   this repo and running `home-manager switch` before Emacs sees it.
10. **Keep the two mechanisms consistent.** If you install the branch via `package-vc`,
    leave `(use-package ghostel :ensure t)` as-is only because it will see the package as
    installed; better, switch that declaration to the `:vc (...)` form so the intent is
    explicit and MELPA cannot re-install the tarball.
11. **A Nix `melpaBuild` override is the reproducible end state**, but the nixpkgs
    derivation would need `src.rev`, `zig_0_16`, and a regenerated `zig.fetchDeps` hash
    (the `files` output already installs the module + sidecar). Weigh that against the
    simpler `package-vc` + local compile route.

---

## Sources

- Branch / diff: [branches API](https://api.github.com/repos/dakra/ghostel/branches),
  [compare `main...fix/pty-winsize-pixels`](https://github.com/dakra/ghostel/compare/main...fix/pty-winsize-pixels),
  [commit `c872539`](https://api.github.com/repos/dakra/ghostel/commits/c872539c20a05c3cfb322211728f25ef0a9f6fec),
  [commit .diff](https://github.com/dakra/ghostel/commit/c872539c20a05c3cfb322211728f25ef0a9f6fec.diff)
- Branch raw files:
  [lisp/ghostel.el](https://raw.githubusercontent.com/dakra/ghostel/fix/pty-winsize-pixels/lisp/ghostel.el),
  [lisp/ghostel-module-install.el](https://raw.githubusercontent.com/dakra/ghostel/fix/pty-winsize-pixels/lisp/ghostel-module-install.el),
  [src/backend_types.zig](https://raw.githubusercontent.com/dakra/ghostel/fix/pty-winsize-pixels/src/backend_types.zig),
  [src/PosixPtyProcess.zig](https://raw.githubusercontent.com/dakra/ghostel/fix/pty-winsize-pixels/src/PosixPtyProcess.zig),
  [src/GhostelTerm.zig](https://raw.githubusercontent.com/dakra/ghostel/fix/pty-winsize-pixels/src/GhostelTerm.zig),
  [src/version.zig](https://raw.githubusercontent.com/dakra/ghostel/fix/pty-winsize-pixels/src/version.zig),
  [build.zig](https://raw.githubusercontent.com/dakra/ghostel/fix/pty-winsize-pixels/build.zig),
  [CHANGELOG.md](https://raw.githubusercontent.com/dakra/ghostel/fix/pty-winsize-pixels/CHANGELOG.md),
  [README.org](https://raw.githubusercontent.com/dakra/ghostel/fix/pty-winsize-pixels/README.org),
  [issue #675](https://github.com/dakra/ghostel/issues/675)
- Emacs manual:
  [Package Installation](https://www.gnu.org/software/emacs/manual/html_node/emacs/Package-Installation.html),
  [Package Files and Directory Layout](https://www.gnu.org/software/emacs/manual/html_node/emacs/Package-Files.html),
  [Fetching Package Sources](https://www.gnu.org/software/emacs/manual/html_node/emacs/Fetching-Package-Sources.html)
- Emacs source consulted locally (Emacs 30.2): `package-vc.el`, `package.el`,
  `use-package-core.el`, `use-package-ensure.el`, `cus-edit.el`.
- MELPA: [recipe `recipes/ghostel`](https://raw.githubusercontent.com/melpa/melpa/master/recipes/ghostel),
  [README / recipe schema](https://github.com/melpa/melpa/blob/master/README.md), [melpa.org](https://melpa.org/)
- Nixpkgs (pinned rev `0bb7ec54c8483066ec9d7720e780a5caa71f8612`):
  [ghostel package.nix](https://github.com/NixOS/nixpkgs/blob/0bb7ec54c8483066ec9d7720e780a5caa71f8612/pkgs/applications/editors/emacs/elisp-packages/manual-packages/ghostel/package.nix),
  [melpa.nix](https://github.com/NixOS/nixpkgs/blob/0bb7ec54c8483066ec9d7720e780a5caa71f8612/pkgs/applications/editors/emacs/build-support/melpa.nix),
  [trivial.nix](https://github.com/NixOS/nixpkgs/blob/0bb7ec54c8483066ec9d7720e780a5caa71f8612/pkgs/applications/editors/emacs/build-support/trivial.nix),
  [all-packages.nix (zig_0_16)](https://github.com/NixOS/nixpkgs/blob/0bb7ec54c8483066ec9d7720e780a5caa71f8612/pkgs/top-level/all-packages.nix)
