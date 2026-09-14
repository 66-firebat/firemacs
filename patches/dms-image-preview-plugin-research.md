# DankMaterialShell (DMS) — Custom Image-Preview Plugin Research

Scope: how to build (or reuse) a DMS/Quickshell plugin that is invoked with an image file
path and renders a preview. Research done against the upstream repo, its in-tree plugin-dev
skill, the official docs, and the community plugin registry. All claims are cited inline.

Versions examined: DMS `master` checkout (`git clone https://github.com/AvengeMedia/DankMaterialShell`)
plus the versioned docs at `1.6` (latest published). Local machine runs Quickshell 0.3.0.

---

## 1. Findings — plugin architecture & discovery

- Plugins are installed as **directories** under `~/.config/DankMaterialShell/plugins/`, each
  containing a `plugin.json` manifest and QML components
  ([docs: Plugins Overview, "Plugin Location"](https://danklinux.com/docs/dankmaterialshell/plugins-overview);
  [upstream `quickshell/PLUGINS/README.md`](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/PLUGINS/README.md)).
- The runtime resolves the directory from Quickshell's config path:
  `readonly property string pluginDirectory: Paths.strip(Paths.config) + "/plugins"`, and also
  scans a **system plugin dir** `/etc/xdg/quickshell/dms-plugins`
  ([`quickshell/Services/PluginService.qml` L22–25](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/Services/PluginService.qml)).
- `PluginService` is a singleton that discovers, validates, loads/unloads, and persists plugin
  state; `PluginsTab.qml` is the Settings UI, and `DankBar.qml` hosts widget components
  ([`PLUGINS/README.md`, "Architecture"](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/PLUGINS/README.md)).
- Discovery happens by scanning the directory tree and reading each `plugin.json`; the service
  also watches the folder (`userWatcher.folder = Paths.toFileUrl(root.pluginDirectory)`,
  [`PluginService.qml` L90](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/Services/PluginService.qml)).
  A rescan can be forced at runtime (see Invocation below).
- Minimum layout
  ([plugin-dev skill: "Minimum plugin structure"](https://github.com/AvengeMedia/DankMaterialShell/blob/master/.agents/skills/dms-plugin-dev/SKILL.md);
  [docs: Plugins Overview](https://danklinux.com/docs/dankmaterialshell/plugins-overview)):

```
~/.config/DankMaterialShell/plugins/YourPlugin/
├── plugin.json          # required manifest
├── YourWidget.qml       # required main QML component (or components map)
├── YourSettings.qml     # optional settings UI
├── StartupCheck.qml     # optional dependency gate
├── *.js                 # optional JS utilities
└── translations/        # optional per-locale JSON
```

- **Plugin types** (declared in `plugin.json`): `widget` (DankBar pill + popout + optional
  Control Center), `daemon` (background service, no UI), `launcher` (searchable items), `desktop`
  (draggable desktop-layer widget), and `composite` (several surfaces in one plugin)
  ([docs: Plugins Overview → Plugin Types](https://danklinux.com/docs/dankmaterialshell/plugins-overview);
  [schema `enum`](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/PLUGINS/plugin-schema.json)).
- Official examples live in [`quickshell/PLUGINS/`](https://github.com/AvengeMedia/DankMaterialShell/tree/master/quickshell/PLUGINS);
  community plugins are indexed at [plugins.danklinux.com](https://plugins.danklinux.com/)
  and in [`AvengeMedia/dms-plugin-registry`](https://github.com/AvengeMedia/dms-plugin-registry).
  First-party plugins live in [`AvengeMedia/dms-plugins`](https://github.com/AvengeMedia/dms-plugins).

### Local environment note

On this machine the custom plugins in the repo
(`/home/fireshark/nixos-dotfiles/git_repositories/DankMaterialShell/plugins/`) are deployed by
home-manager as **Nix-store symlinks** into `~/.config/DankMaterialShell/plugins/<Name>/` (e.g.
`DankSysMonitor/plugin.json -> /nix/store/.../DankSysMonitor/plugin.json`). Registry-installed
plugins appear as symlinks into `~/.config/DankMaterialShell/plugins/.repos/`. So a new custom
plugin should be added to the repo directory and wired through home-manager; dropping it only
into `~/.config/...` may be overwritten on the next home-manager activation.

---

## 2. Plugin schema (`plugin.json`)

The authoritative machine-readable schema is
[`quickshell/PLUGINS/plugin-schema.json`](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/PLUGINS/plugin-schema.json)
(also mirrored as `assets/plugin-schema.json` in the plugin-dev skill). The human-readable field
reference is
[`.agents/skills/dms-plugin-dev/references/plugin-manifest-reference.md`](https://github.com/AvengeMedia/DankMaterialShell/blob/master/.agents/skills/dms-plugin-dev/references/plugin-manifest-reference.md).

### Required fields

| Field | Type | Validation / meaning |
|---|---|---|
| `id` | string | camelCase, `^[a-zA-Z][a-zA-Z0-9]*$`; unique plugin id |
| `name` | string | non-empty human name |
| `description` | string | non-empty, shown in UI |
| `version` | string | semver, e.g. `1.0.0` |
| `author` | string | non-empty |
| `type` | string | one of `widget`, `daemon`, `launcher`, `desktop`, `composite` |
| `capabilities` | array of string | at least 1 (free-form tags: `dankbar-widget`, `control-center`, `daemon`, `launcher`, `desktop-widget`, `ipc`, …) |

### Component selection (exactly one of)

| Field | Type | Meaning |
|---|---|---|
| `component` | string | path to main QML, must match `^\./.*\.qml$` |
| `components` | object | surface map; keys `widget`, `desktop`, `daemon`, `launcher`; each path `^\./.*\.qml$`; ≥1 entry |

### Conditional

| Condition | Required field |
|---|---|
| `type: "launcher"` | `trigger` (string) |
| `components` contains `launcher` | `trigger` |

### Optional fields

| Field | Type | Meaning |
|---|---|---|
| `icon` | string | Material Design icon name for the plugin list |
| `settings` | string | path to settings QML (`^\./.*\.qml$`) |
| `startupCheck` | string | path to non-visual `QtObject` exposing `check(done)` |
| `requires_dms` | string | e.g. `>=1.5.0` |
| `dependencies` | array | system tools (registry metadata) |
| `requires` | array | deprecated alias for `dependencies` |
| `permissions` | array | enum `settings_read`, `settings_write`, `process`, `network` |
| `trigger` | string | launcher trigger, e.g. `=`, `#`, `img` |

`additionalProperties: true`, so custom keys such as the launcher `viewMode` / `viewModeEnforced`
are allowed. `settings_write` is the **only enforced permission**: a plugin with a `settings`
component that omits it shows an error instead of the settings UI
([manifest reference, "Permissions"](https://github.com/AvengeMedia/DankMaterialShell/blob/master/.agents/skills/dms-plugin-dev/references/plugin-manifest-reference.md);
[`PluginSettings.qml` `hasPermission`](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/Modules/Plugins/PluginSettings.qml)).

### Minimal example

```json
{
  "id": "imagePreview",
  "name": "Image Preview",
  "description": "Render a preview of an image file",
  "version": "1.0.0",
  "author": "you",
  "type": "daemon",
  "capabilities": ["ipc"],
  "component": "./ImagePreview.qml",
  "permissions": ["process"]
}
```

### Composite example (daemon + widget surfaces)

```json
{
  "id": "imagePreview",
  "name": "Image Preview",
  "type": "composite",
  "capabilities": ["ipc", "dankbar-widget"],
  "components": { "daemon": "./PreviewDaemon.qml", "widget": "./PreviewWidget.qml" },
  "trigger": "",
  "permissions": ["settings_read", "settings_write"]
}
```
(Composite requires DMS ≥ 1.5.0 — [docs: Composite Plugins](https://danklinux.com/docs/dankmaterialshell/plugins-overview).)

### Plugin API / imports

- Widget/daemon base: `PluginComponent` from `qs.Modules.Plugins`; imports are
  `import QtQuick; import qs.Common; import qs.Widgets; import qs.Modules.Plugins`
  ([`PLUGINS/README.md`, "Widget Component"](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/PLUGINS/README.md)).
- Launcher/desktop base: plain `Item` (launcher) / `DesktopPluginComponent` or `Item` (desktop).
- Theme API from `qs.Common`: `Theme.surfaceContainerHigh`, `Theme.surfaceText`, `Theme.primary`,
  `Theme.spacingM`, `Theme.cornerRadius`, `Theme.fontSizeMedium`, etc.
- Common widgets from `qs.Widgets`: `StyledText`, `StyledRect`, `DankIcon`, `DankButton`,
  `DankGridView`, **`CachingImage`** (see §5).
- Data persistence: `pluginService.savePluginData/loadPluginData`, `savePluginState/loadPluginState`,
  `PluginGlobalVar`, `pluginService.getPluginPath(id)`.
- UI surfaces: `PluginComponent.horizontalBarPill` / `verticalBarPill` (bar widgets),
  `popoutContent` + `popoutWidth/Height` (popout), `ccWidget*`/`ccDetailContent` (Control Center);
  `popoutService` (auto-injected, must be declared as `property var popoutService: null`) can open
  shell popouts/modals; desktop plugins use `DesktopPluginComponent` on the desktop layer
  ([`POPOUT_SERVICE.md`](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/PLUGINS/POPOUT_SERVICE.md)).
  For a true always-on-top arbitrary overlay, a plugin can instantiate a Quickshell `PanelWindow`
  with `Quickshell.Wayland.WlrLayershell` (see Floaty in §6).

---

## 3. Invocation — how to trigger a plugin with a path argument

### The mechanism: `dms ipc call` + `IpcHandler`

Every DMS IPC command uses
`dms ipc call <target> <function> [parameters...]`
([official Keybinds & IPC docs](https://danklinux.com/docs/dankmaterialshell/keybinds-ipc);
[`docs/IPC.md`](https://github.com/AvengeMedia/DankMaterialShell/blob/master/docs/IPC.md)).
A plugin registers its own target by embedding a Quickshell `IpcHandler` and giving it a `target`
string; typed function parameters become CLI arguments. Canonical example in the tree:

```qml
// quickshell/PLUGINS/ExampleCompositePlugin/CompositeDaemon.qml
import Quickshell.Io

IpcHandler {
    target: "compositeExample"
    function runHook(): string { ... return "ran hook"; }
}
```
([source](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/PLUGINS/ExampleCompositePlugin/CompositeDaemon.qml)).
The plugin-dev skill documents the external trigger form as
`dms ipc call myPlugin.toggle` — the same thing with the target/function split
([advanced-patterns.md, "IPC Integration"](https://github.com/AvengeMedia/DankMaterialShell/blob/master/.agents/skills/dms-plugin-dev/references/advanced-patterns.md)).
Arguments are supported: the built-in `plugin-scan` handler is
`function rescan(pluginId: string)` and `function reload(pluginId: string)`
([`PluginService.qml` L1333–1380](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/Services/PluginService.qml)),
and a real third-party plugin takes a path/URL string (see Floaty below).

**Where to put the handler:** in a **daemon** surface. Widget components are instantiated per
bar/section/screen, so a handler placed there can collide; the docs explicitly say launcher
components are lazy and "Put background work (timers, processes, IPC handlers) in a daemon
surface," and use `enabled: root.isDaemonInstance` to register only once
([`PLUGINS/README.md`, Launcher Plugins](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/PLUGINS/README.md);
[Floaty `IpcHandler` with `enabled: root.isDaemonInstance`](https://github.com/hthienloc/dms-floaty/blob/master/FloatyPlugin.qml)).

So the exact invocation for a path-taking plugin is:

```bash
dms ipc call imagePreview show /home/user/photo.png
# or a quoted URL form used by Floaty:
dms ipc call floaty floatFromUrl "file:///home/user/photo.png"
```

Keybind examples (Hyprland) from the Floaty README:
`bind = SUPER, V, exec, dms ipc call floaty floatFromUrl "file:///path/pic.png"`
([Floaty README](https://github.com/hthienloc/dms-floaty/blob/master/README.md)).

### Other invocation routes

- **Widget popout:** `dms ipc call widget toggle <widgetId>`, `openWith <widgetId> <mode>`,
  `openQuery <widgetId> <query>` — but this cannot carry an arbitrary file path into the plugin;
  it only toggles the popout. ([Keybinds & IPC → widget](https://danklinux.com/docs/dankmaterialshell/keybinds-ipc)).
- **Launcher:** `dms ipc call spotlight openQuery <text>` / `launcher openWith files` opens the
  launcher; a launcher plugin then supplies items filtered by its `trigger`
  ([Keybinds & IPC → spotlight](https://danklinux.com/docs/dankmaterialshell/keybinds-ipc)).
- **Plugin management IPC:** `dms ipc call plugin-scan reload <id>` / `scan` / `list` / `status`
  ([`PluginService.qml` L1333+](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/Services/PluginService.qml))
  and `dms ipc call plugins reload <id>` / `enable` / `disable` / `toggle` / `list` / `status`
  ([`DMSShellIPC.qml` L1360–1435](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/DMSShellIPC.qml);
  [dev docs "Live Development"](https://danklinux.com/docs/dankmaterialshell/plugin-development)).
- **DMSIpc broadcast:** plugins can also listen to `DMSIpc`'s `onCommandReceived(command, args)`
  signal instead of owning a target
  ([advanced-patterns.md](https://github.com/AvengeMedia/DankMaterialShell/blob/master/.agents/skills/dms-plugin-dev/references/advanced-patterns.md)).
- **D-Bus:** DMS does **not** document a D-Bus plugin API; the supported external control surface
  is the `dms ipc` CLI / Quickshell IPC socket. (No D-Bus plugin invocation is documented in the
  upstream docs or plugin-dev skill.)

---

## 4. Concrete plugin examples & structure

1. **`LauncherImageExample`** (official, in-tree) — a launcher plugin in **tile/image mode**.
   `plugin.json` adds custom keys `"viewMode": "tile"`, `"viewModeEnforced": true`, `type:
   "launcher"`, `trigger: "img"`; the QML (`QtObject`, not `Item`) implements `getItems(query)`
   returning objects with an `imageUrl`. The README states: "The `imageUrl` property supports
   remote URLs or local files, use `file://` prefix for local files."
   ([example README](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/PLUGINS/LauncherImageExample/README.md);
   [QML](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/PLUGINS/LauncherImageExample/LauncherImageExample.qml)).
   This is the built-in way to show image tiles in the launcher, but it is not a "preview one
   given path now" overlay.

2. **`Floaty`** (third-party, registry + own repo) — the closest existing match to the goal.
   `type: "daemon"`, capabilities `["dankbar-widget", "ipc"]`, and an `IpcHandler` target
   `"floaty"` with `floatFromUrl(url: string)`, `floatFromClipboard()`, `selectFileAndFloat()`,
   etc. `floatFromUrl` calls `spawnWindow(source)`, which validates the local file with
   `file -b <path>`, checks dimensions, and creates a `FloatyWindow.qml` containing a Quickshell
   `PanelWindow` with `WlrLayershell.layer: WlrLayershell.Overlay` — a floating, always-on-top,
   draggable window, rendered with `AnimatedImage { source: window.imageSource }`. It supports
   PNG/JPG/WebP/BMP/SVG and PDF (via `pdftocairo`).
   ([manifest](https://github.com/hthienloc/dms-floaty/blob/master/plugin.json);
   [README](https://github.com/hthienloc/dms-floaty/blob/master/README.md);
   [FloatyPlugin.qml](https://github.com/hthienloc/dms-floaty/blob/master/FloatyPlugin.qml);
   [FloatyWindow.qml](https://github.com/hthienloc/dms-floaty/blob/master/FloatyWindow.qml)).
   Registry entry: ["Floaty — A feature-rich reference image tool to float images, screenshots,
   and vector graphics on top of all windows"](https://github.com/AvengeMedia/dms-plugin-registry/blob/master/plugins/hthienloc-floaty.json).

3. **`FolderView`** (third-party, registry) — `type: "desktop"` with
   `component: "./FolderView.qml"`; its `FolderViewThumbnail.qml` renders local images with a QML
   `Image { source: "file://" + filePath; fillMode: Image.PreserveAspectFit; sourceSize.width: 128;
   sourceSize.height: 128 }`. It also integrates with Floaty ("Float File") for full previews.
   ([manifest](https://github.com/hthienloc/dms-folder-view/blob/master/plugin.json);
   [FolderViewThumbnail.qml](https://github.com/hthienloc/dms-folder-view/blob/master/FolderViewThumbnail.qml);
   [README](https://github.com/hthienloc/dms-folder-view/blob/master/README.md)).

4. **`mediaFrame`** (registry) — `type: "desktop"`, "Desktop plugin to display a picture on your
   desktop" (codeberg.org/claymorwan/dms-plugins, path `mediaFrame`) — a static desktop picture
   frame, not a path-invoked preview
   ([registry entry](https://github.com/AvengeMedia/dms-plugin-registry/blob/master/plugins/claymorwan-media-frame.json)).

---

## 5. Image rendering in QML/Quickshell

- Yes: a QML **`Image`** loads a local file from a URL; `source` is a `url` and "the URL may be
  absolute, or relative to the URL of the component." Local files are addressed with the
  `file://` scheme. PNG/JPEG/SVG/etc. are supported natively.
  ([Qt 6 `Image` QML Type](https://doc.qt.io/qt-6/qml-qtquick-image.html)).
- Practical constraints from the Qt docs (same page):
  - `asynchronous: true` loads local files on a worker thread; default `false` blocks the UI
    thread. Network URLs are always async.
  - `sourceSize` bounds the decoded pixel size (important for large user images to avoid memory
    blowups); changing it re-triggers loading.
  - `fillMode` controls scaling: `Image.PreserveAspectFit` (fit without crop),
    `Image.PreserveAspectCrop` (fill + crop), `Image.Stretch`, `Tile`, `Pad`.
  - `cache` (default true) caches/shared-decodes identical sources; `status` reports
    `Null`/`Loading`/`Ready`/`Error`; `autoTransform` applies EXIF orientation.
- For animated GIF/WebP use **`AnimatedImage`** (Floaty uses `AnimatedImage` for all sources).
- DMS ships **`CachingImage`** (`qs.Widgets`, backed by
  [`dank-qml-common/DankCommon/Widgets/CachingImage.qml`](https://github.com/AvengeMedia/dank-qml-common/blob/master/DankCommon/Widgets/CachingImage.qml)):
  it takes `imagePath` (plain path, `file://`, or http(s)), normalizes/percent-encodes the path,
  uses `Image` for stills and `AnimatedImage` for `.gif`/`.webp`, applies
  `sourceSize`/`fillMode`, and caches grabbed stills under `Paths.imagecache`. Its own comments
  warn to set `animate: false` for thumbnail grids.
- The `imageUrl` field used by launcher tile mode "supports remote URLs or local files, use
  `file://` prefix for local files"
  ([LauncherImageExample README](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/PLUGINS/LauncherImageExample/README.md)).

---

## 6. Existing image/file preview plugins

**Yes — a very close one exists: [Floaty](https://github.com/hthienloc/dms-floaty)** by
Loc Huynh, listed in the official registry as
[`hthienloc-floaty`](https://github.com/AvengeMedia/dms-plugin-registry/blob/master/plugins/hthienloc-floaty.json):

- Purpose: "A feature-rich reference image tool to float images, screenshots, and vector graphics
  on top of all windows."
- Type `daemon`, capability `ipc`; exposes
  `dms ipc call floaty floatFromUrl "file:///path/to/image"` **exactly** the requested
  invoke-with-a-path behavior.
- Renders in a `PanelWindow` with `WlrLayershell.layer: Overlay` (always on top), using
  `AnimatedImage`; supports PNG/JPG/WebP/BMP/SVG and PDF, plus move/resize/minimize/close.
- Install: `dms plugins install floaty` (or clone into `~/.config/DankMaterialShell/plugins/`).

Other adjacent, but not matching, plugins found in the registry scan:

- [`quickCapture`](https://github.com/AvengeMedia/dms-plugin-registry/blob/master/plugins/hthienloc-quick-capture.json)
  — screenshot annotation/recording; has an `openImage` IPC used by Floaty's "edit" action.
- [`ocrScanner`](https://github.com/AvengeMedia/dms-plugin-registry/blob/master/plugins/hthienloc-ocr-scanner.json)
  — reads text from clipboard/local image files (renders/uses images, but for OCR).
- [`folderView`](https://github.com/AvengeMedia/dms-plugin-registry/blob/master/plugins/hthienloc-folderView.json)
  — file browser with live thumbnails.
- [`imageConverter`](https://github.com/AvengeMedia/dms-plugin-registry/blob/master/plugins/murilo-gotardo-image-converter.json)
  — format conversion from the bar.
- [`latex2svg`](https://github.com/AvengeMedia/dms-plugin-registry/blob/master/plugins/kinnariyamamatanha-latex2svg.json)
  — sharp SVG preview of generated formulas.
- [`mediaFrame`](https://github.com/AvengeMedia/dms-plugin-registry/blob/master/plugins/claymorwan-media-frame.json)
  — desktop picture frame.
- Official launcher tile demo [`LauncherImageExample`](https://github.com/AvengeMedia/DankMaterialShell/tree/master/quickshell/PLUGINS/LauncherImageExample)
  — image gallery inside the launcher.

No registry plugin is a generic "single-shot image preview invoked with a path" other than
Floaty; a keyword scan of all 363 registry manifests for quick-look / file-preview style
descriptions found none. So: **Floaty already does it; only a custom plugin is needed if you want
different UX (e.g. a popout instead of a floating window, no PDF dependency, or tighter DMS
integration).**

---

## 7. Packaging / installation

- Manual: place the directory in `~/.config/DankMaterialShell/plugins/` (or
  `/etc/xdg/quickshell/dms-plugins` for system-wide), then `dms restart`
  ([docs: Installation](https://danklinux.com/docs/dankmaterialshell/plugins-overview);
  [PluginService.qml L25](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/Services/PluginService.qml)).
- Registry CLI: `dms plugins install <name>` / `dms plugins search` / `dms plugins list`;
  managed installs are recorded in `~/.config/DankMaterialShell/plugins.lock.json`
  ([registry README](https://github.com/AvengeMedia/dms-plugin-registry/blob/master/README.md);
  [DMS README](https://github.com/AvengeMedia/DankMaterialShell/blob/master/README.md)).
- Enablement state and per-plugin settings live in the DMS config (`settings.json` /
  `plugin_settings.json`). In this environment `plugin_settings.json` currently keys entries by
  plugin id with `{"enabled": true}` (local file
  `/home/fireshark/nixos-dotfiles/git_repositories/DankMaterialShell/plugin_settings.json`).
- GUI: Settings → Plugins → **Scan for Plugins** → toggle on; add to DankBar layout for widgets
  ([docs: Enable Plugin](https://danklinux.com/docs/dankmaterialshell/plugins-overview)).
- Dev loop: symlink the plugin dir and reload without restarting:
  `ln -sf <devdir> ~/.config/DankMaterialShell/plugins/MyPlugin` then
  `dms ipc call plugins reload myPlugin`
  ([dev docs: Live Development](https://danklinux.com/docs/dankmaterialshell/plugin-development)).
- Validate the manifest with `jq . plugin.json` or JSON-Schema validation against
  [`plugin-schema.json`](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/PLUGINS/plugin-schema.json)
  ([skill Step 11](https://github.com/AvengeMedia/DankMaterialShell/blob/master/.agents/skills/dms-plugin-dev/SKILL.md)).

---

## 8. Recommendation

### Option A — Reuse Floaty (recommended if the floating-window UX is acceptable)

Install it and bind/call the existing IPC command:

```bash
dms plugins install floaty
dms ipc call floaty floatFromUrl "file:///absolute/path/to/image.png"
# Hyprland:
bind = SUPER, P, exec, dms ipc call floaty floatFromUrl "$(wl-paste)"
```

Pros: already implements path input, overlay rendering, validation, zoom/resize, PDF support; no
new code. Cons: pulls in `poppler-utils`; its IPC target is `floaty` (not your own); UX is a
free-floating always-on-top window, not a DMS-themed popout. Sources:
[Floaty README](https://github.com/hthienloc/dms-floaty/blob/master/README.md),
[registry entry](https://github.com/AvengeMedia/dms-plugin-registry/blob/master/plugins/hthienloc-floaty.json).

### Option B — Write a minimal custom plugin (if you want your own IPC target / themed popout)

Use a **composite** plugin: a `daemon` surface that owns the `IpcHandler` and creates the preview
window, optionally plus a `widget` surface for a bar button. This follows the documented rule
"put IPC handlers in a daemon surface."

```
~/.config/DankMaterialShell/plugins/ImagePreview/
├── plugin.json
├── PreviewDaemon.qml   # daemon surface: IpcHandler target "imagePreview"
├── PreviewWindow.qml   # Quickshell PanelWindow + Image overlay
└── PreviewSettings.qml # optional
```

`plugin.json`:

```json
{
  "id": "imagePreview",
  "name": "Image Preview",
  "description": "Show a preview overlay for an image path",
  "version": "1.0.0",
  "author": "fireshark",
  "icon": "image",
  "type": "composite",
  "capabilities": ["ipc"],
  "components": { "daemon": "./PreviewDaemon.qml" },
  "requires_dms": ">=1.5.0",
  "permissions": ["process"]
}
```

`PreviewDaemon.qml` (pattern proven by Floaty + `ExampleCompositePlugin/CompositeDaemon.qml`):

```qml
import QtQuick
import Quickshell.Io          // IpcHandler
import qs.Common
import qs.Modules.Plugins

PluginComponent {
    id: root
    property var popoutService: null

    function toFileUrl(p) {
        if (p.startsWith("file://") || p.startsWith("http")) return p;
        return "file://" + p.split('/').map(s => encodeURIComponent(s)).join('/');
    }

    function show(path) {
        if (!path) return;
        const win = winComponent.createObject(root, { imageSource: toFileUrl(path) });
        root.openWindows = [...root.openWindows, win];
    }
    property var openWindows: []

    IpcHandler {
        target: "imagePreview"          // dms ipc call imagePreview show <path>
        // A daemon surface is instantiated once, so no extra guard is needed.
        // If you also add a widget surface, prefer registering the handler only
        // in the daemon (e.g. `enabled: <isDaemonInstance>` as Floaty does).
        function show(path: string): string {
            root.show(path);
            return "SUCCESS";
        }
        function closeAll(): string {
            root.openWindows.forEach(w => w.destroy());
            root.openWindows = [];
            return "SUCCESS";
        }
    }

    Component { id: winComponent; PreviewWindow {} }
}
```

`PreviewWindow.qml` (minimal overlay; `sourceSize` bounds decode memory, `asynchronous` keeps UI
responsive; both per the Qt Image docs):

```qml
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common

PanelWindow {
    id: win
    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    WlrLayershell.namespace: "dms-image-preview"
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusiveZone: -1
    property string imageSource: ""

    Rectangle {
        anchors.fill: parent
        color: Theme.surfaceContainer
        opacity: 0.98
        Image {
            anchors.centerIn: parent
            width: parent.width * 0.9
            height: parent.height * 0.9
            source: win.imageSource
            asynchronous: true
            cache: false
            fillMode: Image.PreserveAspectFit
            sourceSize.width: 2048
            sourceSize.height: 2048
        }
        MouseArea { anchors.fill: parent; onClicked: win.destroy() }
    }
}
```

Invoke: `dms ipc call imagePreview show /home/user/photo.png`
(and `dms ipc call imagePreview closeAll`). Bind in Hyprland:
`bind = SUPER, P, exec, dms ipc call imagePreview show "$(wl-paste)"`.

Alternative for a DMS-native look with no extra window: make it a **launcher** plugin with
`"viewMode": "tile"` and return an item whose `imageUrl: "file:///..."` — then open it with
`dms ipc call spotlight openWith files` after writing the path into plugin state. This reuses
DMS's image-tile rendering but is more indirect than a PanelWindow. See
[LauncherImageExample](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/PLUGINS/LauncherImageExample/README.md)
and the [launcher dev guide](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/PLUGINS/README.md).

**Bottom line:** QML `Image`/`AnimatedImage` can render a local file path at runtime; DMS's
supported invocation channel is `dms ipc call <target> <function> [args...]` with the plugin
registering a Quickshell `IpcHandler` in a daemon surface; an existing plugin (Floaty) already
implements exactly this for image paths, so a custom plugin is only required if you want a
different UX or your own command target.

---

### Source index

- Upstream repo: <https://github.com/AvengeMedia/DankMaterialShell>
- Plugin schema: <https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/PLUGINS/plugin-schema.json>
- In-tree plugin system docs: <https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/PLUGINS/README.md>
- In-tree plugin-dev skill: <https://github.com/AvengeMedia/DankMaterialShell/blob/master/.agents/skills/dms-plugin-dev/SKILL.md>
- Official docs (Plugins Overview): <https://danklinux.com/docs/dankmaterialshell/plugins-overview>
- Official docs (Plugin Development): <https://danklinux.com/docs/dankmaterialshell/plugin-development>
- Official docs (Keybinds & IPC): <https://danklinux.com/docs/dankmaterialshell/keybinds-ipc>
- IPC reference: <https://github.com/AvengeMedia/DankMaterialShell/blob/master/docs/IPC.md>
- Plugin registry: <https://plugins.danklinux.com/> / <https://github.com/AvengeMedia/dms-plugin-registry>
- First-party plugins: <https://github.com/AvengeMedia/dms-plugins>
- Floaty: <https://github.com/hthienloc/dms-floaty>
- Shared widget lib: <https://github.com/AvengeMedia/dank-qml-common>
- Qt `Image`: <https://doc.qt.io/qt-6/qml-qtquick-image.html>
- Quickshell `PanelWindow`: <https://quickshell.org/docs/v0.2.0/types/Quickshell/PanelWindow/>
