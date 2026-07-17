# Grease MELPA Bringup

## Goal

Publish `grease.el` on [MELPA](https://melpa.org) so users can install it with
`M-x package-install RET grease RET` or `(use-package grease :ensure t)`.

## Current state

| Item | Status |
|------|--------|
| GitHub repo | ✅ `github.com/mwac-dev/grease.el` |
| `provide` form | ✅ `(provide 'grease)` at line 3546 |
| Package headers | ❌ Missing `Version`, `Package-Requires`, `Author`, `URL`, `Keywords` |
| GPL license boilerplate | ❌ Missing |
| package-lint | ❌ Not run |
| Byte-compile clean | ❓ Unknown (likely warnings) |
| Git tags | ❌ No release tag yet |
| MELPA recipe | ❌ Not submitted |

---

## Step-by-step checklist

### 1. Add package headers to `grease.el` (required)

Replace the current header block (lines 1–11) with:

```elisp
;;; grease.el --- An oil.nvim-style file manager for Emacs -*- lexical-binding: t; -*-

;; Author: MWAC-dev <your-email@example.com>
;; Maintainer: MWAC-dev <your-email@example.com>
;; Version: 0.5.0
;; Package-Requires: ((emacs "28.1"))
;; Keywords: files, tools, convenience
;; URL: https://github.com/mwac-dev/grease.el

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.
```

**`Package-Requires` notes:**
- `emacs "28.1"` — minimum Emacs version (you use `cl-lib`, `subr-x`; both are built-in since 24.4).
- `nerd-icons` and `evil` are optional (`eval-when-compile` with `nil t`), so they do **not** go in `Package-Requires`.
- `cl-lib` is bundled with Emacs — omit it from `Package-Requires`.

### 2. Run `package-lint` and fix all warnings (required)

```bash
# In Emacs:
M-x package-install RET package-lint RET
M-x package-lint-current-buffer RET
```

Likely issues to fix:
- `defvar` without docstring → add docstrings
- `defcustom` missing `:type` or `:group` → verify every defcustom
- Private `grease--foo` functions called from outside → rename public-facing functions
- `(provide 'grease)` mismatch with filename → already correct
- Unused lexical variables → prefix with `_` or remove

**Target: zero warnings.**

### 3. Byte-compile cleanly (required)

```bash
emacs -Q --batch -L . -f batch-byte-compile grease.el
```

**Target: zero warnings.** Fix:
- Unused variable warnings
- Free variable reference warnings
- Obsolete function call warnings

### 4. Clean up the repository (recommended)

```bash
# Add to .gitignore if not already present:
echo "*.elc" >> .gitignore

# Remove any existing .elc files from version control:
git rm --cached *.elc 2>/dev/null

# Remove any backup files:
git rm --cached *~ \#*\# 2>/dev/null
```

### 5. Tag a release (recommended for MELPA Stable)

```bash
git tag v0.5.0
git push origin v0.5.0
```

Without a tag, MELPA builds from HEAD but MELPA Stable won't pick it up.

### 6. Decide plugins strategy

| Option | Description |
|--------|-------------|
| **A — Single package** | `plugins/*.el` shipped inside `grease`; users `require` manually. Simplest. |
| **B — Multi-package** | Separate MELPA recipes for `grease`, `grease-eat`, etc. Each plugin gets its own `Package-Requires`. |
| **C — Spin off** | Move `eat-grease.el` to the Eat project or its own repo. Keeps Grease lean. |

**Recommendation: start with Option A (single package).** Revisit after 3+ plugins and real user demand for granular installs.

### 7. Submit MELPA recipe PR

Fork [github.com/melpa/melpa](https://github.com/melpa/melpa) and add `recipes/grease`.

#### Dependency analysis

`grease.el` requires nothing outside Emacs core:

```
(require 'cl-lib)       ;; built-in since Emacs 24.3
(require 'subr-x)       ;; built-in since Emacs 24.4
```

Compile-time (optional, non-fatal if missing):

```
(eval-when-compile (require 'nerd-icons nil t))  ;; icons — optional
(eval-when-compile (require 'evil nil t))        ;; vim bindings — optional
```

Neither `nerd-icons` nor `evil` belongs in `Package-Requires` because the
`nil t` form means "don't error if not found." Grease degrades gracefully
without them.

#### Current repo contents

```
repo root:
├── grease.el          ← main package (required)
├── grease-test.el     ← tests (do NOT ship in the package)
├── eat-grease.el      ← Eat integration plugin (separate concern)
└── README.org         ← documentation (ship with package)
```

#### Sample recipe (Option A — single package, recommended starting point)

```elisp
(grease
 :fetcher github
 :repo "mwac-dev/grease.el"
 :files ("grease.el" "README.org"))
```

**Why this `:files` value:**

| File | Included? | Reason |
|------|-----------|--------|
| `grease.el` | ✅ Yes | The package itself. Must be present. |
| `README.org` | ✅ Yes | MELPA convention — provides a `-readme` artifact on the package page. |
| `grease-test.el` | ❌ No | Tests. Shipping this would add it to every user's `load-path` unnecessarily. |
| `eat-grease.el` | ❌ No | Integration plugin requiring the `eat` package. Shipping this would make `eat` a transitive dependency of Grease — incorrect. Loaded separately by users who want it via `(require 'eat-grease)`. |

#### If shipping plugins later (Option B — multi-package)

When the plugins directory exists with 3+ plugins, submit separate recipes:

```elisp
;; recipes/grease — core package (unchanged)
(grease
 :fetcher github
 :repo "mwac-dev/grease.el"
 :files ("grease.el" "README.org"))

;; recipes/grease-eat — Eat integration (separate package)
(grease-eat
 :fetcher github
 :repo "mwac-dev/grease.el"
 :files ("plugins/eat.el")
 :version-regexp "v?\\([0-9]+\.[0-9]+\.[0-9]+\\)")
```

Each plugin file then needs its own `Package-Requires` header, e.g.:

```elisp
;;; plugins/eat.el --- Eat integration for Grease  -*- lexical-binding: t; -*-
;; Package-Requires: ((emacs "28.1") (grease "0.5") (eat "0.9"))
```

#### With version tags (MELPA Stable support)

```elisp
(grease
 :fetcher github
 :repo "mwac-dev/grease.el"
 :files ("grease.el" "README.org")
 :version-regexp "v?\\([0-9]+\.[0-9]+\.[0-9]+\\)")
```

The `:version-regexp` tells MELPA Stable to build from git tags matching
`v0.5.0`, `0.5.0`, `v1.0.0`, etc. Without it, MELPA Stable falls back to
timestamp-based versions (e.g. `20250717.1200`).

### 8. Optional: Add `grease-mode-hook` and extension hooks (quality-of-life)

Before applying to NonGNU ELPA later, add proper hooks so plugins use `add-hook` instead of `advice-add`:

```elisp
(defcustom grease-visit-hook nil
  "Hook run after Grease visits a file or directory.
Called with one argument, a plist with keys :name, :type, :path, etc."
  :type 'hook
  :group 'grease)

(defcustom grease-quit-hook nil
  "Hook run before Grease quits a buffer."
  :type 'hook
  :group 'grease)

(defcustom grease-open-hook nil
  "Hook run after a new Grease buffer is opened."
  :type 'hook
  :group 'grease)
```

Not required for MELPA, but strongly recommended for long-term maintenance and NonGNU ELPA eligibility.

---

## Archive comparison (reference)

| | MELPA | NonGNU ELPA | GNU ELPA |
|---|---|---|---|
| FSF copyright assignment | No | No | **Yes** |
| Ships built-in with Emacs | No | Yes (28+) | Yes (24+) |
| Recipe location | PR to `melpa/melpa` | `elpa-packages` in emacs.git | Manual tarball |
| Barrier to entry | Lowest | Medium | High |
| Visibility | Requires `add-to-list` | `M-x list-packages` out of the box | `M-x list-packages` out of the box |
| Recommended first target | **← start here** | After MELPA stability (3–6 months) | Only if FSF assignment desired |

---

## MELPA build lifecycle (how it works once published)

```
git push to main
    │
    ▼
MELPA build server detects new commit (polls every ~1 hour)
    │
    ▼
Clones repo, byte-compiles, runs package-lint
    │
    ▼
On success → tarball published to https://melpa.org/packages/grease-*.tar
On failure → build log at https://melpa.org/builds/grease.html
    │
    ▼
Users run M-x package-refresh-contents → M-x package-install RET grease RET
```

---

## Post-publication user onboarding

After grease is on MELPA, the user setup becomes:

```elisp
;; Minimal setup — for users who just want Grease
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/"))
(package-initialize)

(use-package grease
  :ensure t
  :bind ("C-c g" . grease-open)
  :config
  (setq grease-show-hidden t))
```

No more `:load-path "~/path/to/grease"` needed. Just `:ensure t`.
