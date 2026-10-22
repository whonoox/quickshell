# One-Click Installable Nooxshell for Omarchy

Implementation plan for distributing the floating-island desktop shell as a
one-command install on any Omarchy machine, following the patterns of
[Caelestia Shell](https://github.com/caelestia-dots/shell) (declarative
manifest, state tracking, a dedicated management CLI, non-destructive config
integration).

Everything in this document has been verified against a live Omarchy 4.0.4
system running Hyprland 0.56.2 and Quickshell 0.3.1.

---

## 1. What Is Actually Installed

The shell is a Quickshell config: a root `Scope` that mounts floating
"island" panels over the Omarchy desktop. The stock Omarchy shell keeps
running; the islands layer on top of it.

```
quickshell/                          (this repository)
├── install.sh                       one-click installer
├── uninstall.sh                     atomic rollback uninstaller
├── manifest.json                    declarative deployment manifest
├── bin/
│   └── nooxshell                    management CLI
├── hypr/
│   └── quickshell-islands.lua       Hyprland bindings, layer rules, autostart
├── shims/                           command interceptors installed to ~/.local/bin
├── *.qml, *.js                      the shell itself (25 files)
└── decorations/*.svg                vector assets (10 files)```

### Two Quickshell instances, always

| Instance | Config path | Started by | Role |
| :--- | :--- | :--- | :--- |
| Stock Omarchy | `/usr/share/omarchy/shell` | `omarchy-launch-shell` | Bar, lock screen, OSD, notifications service |
| Islands | `~/.config/quickshell` | `o.launch_on_start("qs --no-duplicate")` | Floating island panels |

**Every** `qs` invocation must therefore name the instance explicitly with
`--path`. A bare `qs kill` or `qs ipc call` can reach the wrong one.

---

## 2. Verified Facts

These are the load-bearing details. Each was checked on the live system, not
inferred.

### 2.1 IPC targets

`qs ipc show` against the islands config lists exactly these targets:

| Friendly name | IPC target | Toggle function | Notes |
| :--- | :--- | :--- | :--- |
| `menu` | `omarchyMenu` | `toggle(route)` | Requires a route argument; defaults to `root` |
| `wifi` | `wifiBar` | `toggle` | Void return |
| `bluetooth` | `bluetoothBar` | `toggle` | Void return |
| `time` | `timeBar` | `toggle` | Void return |
| `audio` | `audioBar` | `toggle` | Returns `open`/`closed` |
| `battery` | `batteryBar` | `toggle` | Void return |
| `brightness` | `brightnessBar` | `toggle` | Returns `open`/`closed` |
| `wallpaper` | `wallpaperPicker` | `toggle` | Returns `ok` |
| `notifications` | `notifications` | `toggleDnd` | Not named `toggle`; returns void |

`qs ipc call` **always exits 0**, even when it prints `Target not found.` or
`Function not found.`. Callers must inspect the reply text, not the exit
status. A void handler prints an empty string, which is a success.

### 2.2 Layer namespaces

The X-Ray blur rule must match the namespaces the panels actually declare via
`WlrLayershell.namespace`:

```
workspaces-panel-main   time-panel-main        wifi-panel-main
bluetooth-panel-main    audio-panel-main       brightness-panel-main
battery-panel-main      notification-panel-main
quickshell-omarchy-menu scoop-v2-inspector     quickshell
```

Deliberately **excluded**: `quickshell-wallpaper-grid` (opaque backdrop),
`wifi-panel-twin-dismiss` and `bluetooth-panel-twin-dismiss` (transparent
click-catchers). Blurring them costs a pass and changes nothing.

### 2.3 Hyprland Lua module resolution

Omarchy's Lua bootstrap (`/usr/share/omarchy/default/hypr/bootstrap.lua`) sets:

```lua
package.path = home .. "/.local/state/?.lua;"
  .. home .. "/.config/?.lua;"
  .. (os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/?.lua;"
  .. package.path
```

So a file at `~/.config/hypr/quickshell-islands.lua` is reached as
`require("hypr.quickshell-islands")` — the `hypr.` prefix is what maps
`hypr/x.lua` onto the path. The prefix is also required for hot reload: the
bootstrap only clears `package.loaded` for the `default.hypr`, `hypr` and
`omarchy.current.theme` prefixes, so a top-level module name would never
re-execute on `hyprctl reload`.

### 2.4 Quickshell pragmas

Pragmas are only honored **before the first `import` statement** in the root
file. Placed after it, they are silently ignored.

```qml
//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1
//@ pragma DefaultEnv QSG_RENDER_LOOP=threaded
import Quickshell
```

`QS_DROP_EXPENSIVE_FONTS` only excludes `woff`/`woff2` files. It does not
help with font-cache problems and is not needed here.

The root file needs no `import QtQuick`: `Scope` comes from Quickshell, and
the shell does not load fonts itself — the brand font is resolved through
fontconfig (see §2.5).

### 2.5 Font family

`fc-query` reports the family as `Nuuxfont` (not `NuuXFont`). `Theme.qml`
uses `"Nuuxfont"`, which matches.

The brand font is **not distributed with the shell**. It is a personal
typeface, and the repository is public, so the font file is not committed
and the installer does not deploy it. Instead:

- The font is expected to be installed system-wide on the machines that
  have it, where fontconfig makes it visible to every application. On
  this system it lives in `/usr/share/fonts/NuuXFont/`.
- `Theme.qml` resolves the family at runtime from `Qt.fontFamilies()` and
  falls back to the system font when it is absent, so a machine without
  the font renders correctly instead of with a missing family.
- The installer checks for the font and prints how to install it if it is
  missing. This is a warning, not an error.

To install it on another machine:

```bash
sudo install -Dm644 Nuuxfont-Regular.ttf /usr/share/fonts/NuuXFont/
fc-cache -f
```

`QS_DROP_EXPENSIVE_FONTS` only excludes `woff`/`woff2` files and is not
needed here.

### 2.6 Shell lifecycle

- `qs -d -n -p <path>` starts a detached instance. `-d` is required; without
  it the process runs in the foreground.
- `qs kill -p <path>` is scoped to the config path.
- After a kill, the old instance's lock stays registered briefly. `qs -n`
  then refuses with `An instance of this configuration is already running.`
  The CLI retries until the lock clears.
- `qs ipc call` and `qs list` both accept `--path`.

### 2.7 Shell.json

The stock shell's plugins are suppressed through `disabledPlugins` in
`~/.config/omarchy/shell.json`. Omarchy ships
`/usr/share/omarchy/bin/omarchy-shell-config`, a helper that normalizes the
file and commits it atomically. The installer sources that helper rather
than hand-rolling a `jq` pipeline, so the file keeps Omarchy's shape.

### 2.8 Dependencies

Actual external commands used by the shell and its shims:

| Package | Provides |
| :--- | :--- |
| `quickshell` | `qs` |
| `hyprland` | `hyprctl` |
| `omarchy` | `omarchy-shell`, `omarchy-menu`, `omarchy-bluetooth-device`, `omarchy-network-band` |
| `networkmanager` | `nmcli` |
| `wireplumber` | `wpctl` |
| `libpulse` | `pactl` |
| `upower` | battery status |
| `awww` | `awww`, `awww-daemon` |
| `brightnessctl` | backlight control |
| `jq` | menu and network JSON |
| `fontconfig` | `fc-cache` |
| `inotify-tools` | `inotifywait` for the wallpaper bridge |

`pamixer`, `wl-clipboard` and `bluez`/`bluetoothctl` are **not** used: the
audio shim drives `wpctl`/`pactl`, and Bluetooth goes through
`omarchy-bluetooth-device`.

### 2.9 Shims

Thirteen scripts install into `~/.local/bin`, which must precede `/usr/bin`
in `PATH` for them to shadow the packaged commands.

They must be installed **flat into one directory**: `omarchy` locates
`omarchy-menu` beside itself, and the menu shims source
`_omarchy-menu-shim` from their own directory. `_omarchy-menu-shim` is
sourced rather than executed, so it keeps mode `0644`.

| Shim | Mode | Purpose |
| :--- | :--- | :--- |
| `omarchy` | 0755 | Pass-through; re-routes only the `menu` group |
| `omarchy-shell` | 0755 | Intercepts OSD show/hide, routes to the islands |
| `omarchy-osd` | 0755 | Volume/brightness OSD interception |
| `omarchy-menu` | 0755 | Menu entry point |
| `omarchy-menu-input` | 0755 | Scripted menu input |
| `omarchy-menu-select` | 0755 | Scripted menu selection |
| `_omarchy-menu-shim` | 0644 | Shared plumbing, sourced by the three above |
| `omarchy-audio-output-volume` | 0755 | Volume keys to the audio HUD |
| `omarchy-brightness-display` | 0755 | Brightness keys to the brightness HUD |
| `omarchy-brightness-display-ddc` | 0755 | Same, for DDC/CI external displays |
| `omarchy-theme-bg-set` | 0755 | Sets the background and syncs awww |
| `omarchy-theme-bg-switcher` | 0755 | Opens the Quickshell wallpaper picker |
| `awww-omarchy-bridge` | 0755 | Keeps awww in sync with Omarchy's background state |

`omarchy-theme-bg-switcher` and `awww-omarchy-bridge` previously existed
only in `~/.local/bin` with no source in the repository. They are now
versioned here, so the manifest can deploy them.

---

## 3. The Manifest

`manifest.json` is the single source of truth. It declares the shell files,
the shims, the font, the Hyprland module, the dependencies, the state
locations and the post-install hooks.

```json
{
  "name": "omarchy-quickshell-islands",
  "version": "1.0.0",
  "shell":    { "configPath": "~/.config/quickshell", "root": "shell.qml" },
  "state":    { "dir": "~/.local/state/nooxshell", "manifest": "state.json" },
  "files":    [ { "src": "shell.qml", "dest": "~/.config/quickshell/shell.qml" } ],
  "shims":    [ { "src": "shims/omarchy", "dest": "~/.local/bin/omarchy", "mode": "0755" } ],
  "hypr":     { "module": { "src": "hypr/quickshell-islands.lua", "dest": "~/.config/hypr/..." } },
  "dependencies": { "pacman": [ "quickshell", "hyprland", "..." ] },
  "hooks":    { "post_install": [ "hyprctl reload", "nooxshell restart" ] }
}
```

`files` is what makes the install manifest-driven. Without it, a
manifest-driven installer deploys zero shell.

---

## 4. The Hyprland Integration

One module, `hypr/quickshell-islands.lua`, owns everything the islands need
from Hyprland:

- the global shortcuts (unbind the Omarchy default, then bind the
  `quickshell:*` dispatcher, which routes straight into the shell's event
  loop with no process spawn)
- the hardware keys (volume and brightness, which the shims answer)
- the X-Ray blur layer rule
- the autostart of the wallpaper bridge and the shell itself

`install.sh` deploys it to `~/.config/hypr/quickshell-islands.lua` and adds
one fenced block to `~/.config/hypr/hyprland.lua`:

```lua
-- quickshell-islands:begin
require("hypr.quickshell-islands")
-- quickshell-islands:end
```

The markers make the injection idempotent (re-running the installer replaces
the block instead of appending a second one) and give the uninstaller an
exact target for removal.

Because the module now owns these settings, the installer removes the
equivalent hand-written blocks from `bindings.lua`, `looknfeel.lua` and
`autostart.lua`. Without that step the shortcuts would be bound twice and
`qs` would be launched twice.

---

## 5. The Installer

`install.sh` runs these steps:

1. **Parse flags** — `--dry-run`, `--yes`, `--skip-deps`, `--no-start`.
2. **Check dependencies** — packages from the manifest. `sudo pacman -S` is
   only run from an interactive terminal; a piped `curl | bash` has no tty
   to prompt on, so the script tells the user what to run instead.
3. **Back up** — every file it is about to touch is copied into
   `~/.local/state/nooxshell/backups/<timestamp>/files/`, with the
   list of backed-up paths in `backup_manifest.json`.

   A second, permanent copy goes to `~/.local/state/nooxshell/pristine/`.
   It is written **once** and never overwritten: a later install would
   otherwise capture the files the first install already deployed, and the
   uninstaller would restore the installer's own copies instead of the
   user's originals. The uninstaller restores from `pristine/`, not from the
   newest per-run backup.
4. **Deploy** — the shell files, the shims, the font, the Hyprland module
   and the CLI, all driven by the manifest.
5. **Deconflict Hyprland** — strip the now-duplicated hand-written blocks.
6. **Configure Omarchy** — add the disabled plugin ids to `shell.json` via
   Omarchy's own `omarchy-shell-config` helper.
7. **Write state** — `~/.local/state/nooxshell/state.json` records
   the version, timestamp, repo path, config path and the Hyprland paths, so
   `update` and `uninstall` know exactly what they own.
8. **Verify** — every manifest entry must exist, every shim must be
   executable (except the `0644` sourced helper).
9. **Activate** — the hooks named in `manifest.json` are run, with the
   config path they were installed to passed explicitly so a hook never
   resolves a different tree from `$HOME`. `--no-start` skips the hook
   that starts the shell.

### A note on `set -e` and counters

`(( waited++ ))` returns exit status 1 when the variable is 0, because
post-increment yields the old value. Under `set -e` that kills the script
silently, with no output. Use `waited=$((waited + 1))` instead.

The same trap applies to any conditional as the last statement of a
function. `[[ -n $reply ]] && echo "$reply"` returns 1 when the reply is
empty, which is exactly the success case for a void IPC handler, and it
aborts the script. Use an `if` block instead.

A command substitution whose command can exit non-zero has the same problem:
`bin_dir="$(... | grep -n -x "$BIN_DIR" | ...)"` aborts the install when
the path is not in `PATH`. Add `|| true` and check the result explicitly.

### A note on stale installs

The CLI is deployed to `~/.local/bin/nooxshell`. Editing the copy in
the repository does not change the installed one, so a bug fix can appear
to have no effect. Re-run `./install.sh` after changing the CLI, or invoke
`bin/nooxshell` directly from the repository to test the new code.

---

## 6. The Management CLI

`bin/nooxshell` installs to `~/.local/bin/nooxshell`. It was previously
called `omarchy-islands`; the installer migrates an older installation's
state directory and removes the old command.

```
nooxshell start                Start the shell if it is not running
nooxshell stop                 Stop this shell's instance
nooxshell restart              Stop and start again
nooxshell log [-f] [-n N]      Show logs; -f follows, -n limits
nooxshell status               Instance, IPC health, available targets
nooxshell doctor [--fix]       Check for stray instances and theme problems
nooxshell toggle <module>      Toggle an island panel
nooxshell ping                 Check that the shell answers
nooxshell update               Pull the newest revision and restart
nooxshell uninstall            Remove the shell, restore the desktop
```

Every command passes `--path` to `qs`, so the stock Omarchy shell is never
touched. `toggle` maps the friendly names in §2.1 onto real targets and
functions, supplies `root` for the menu's required route argument, and
treats an empty reply as success.

### Stray instances

A second Quickshell instance drawing the same panels shows up as a doubled
desktop: one set of panels in the live theme colors and one in the default
palette. The cause is always the same — the stray runs with a `HOME` that
has no `~/.local/state/omarchy/current/theme/colors.toml`, so `Theme.qml`
falls back to its hardcoded palette.

`status` lists any instance other than the islands shell and the stock
Omarchy shell. `doctor` additionally checks that the theme file is present
and can stop the strays:

```bash
nooxshell doctor        # report
nooxshell doctor --fix  # stop them
```

Two rules keep strays from appearing in the first place:

- The installer passes the config path it just deployed to the activation
  hooks, so a hook never resolves a different tree from `$HOME`.
- `install.sh --no-start` skips the hook that starts the shell. Use it for
  any install that points `HOME` at a scratch directory: a shell started
  there survives the directory being deleted and keeps drawing panels over
  the real desktop.

---

## 7. The Uninstaller

`uninstall.sh` reverses the install precisely:

1. Stops this shell's instance.
2. Restores every file from the pristine backup taken before the first
   install.
3. Removes the files the installer created that had no previous version.
   Files covered by the pristine backup are restored, not deleted.
4. Removes the Hyprland module and strips the fenced require block.
5. Restores `shell.json`.
6. Reloads Hyprland and restarts the stock Omarchy shell.

The install/uninstall round trip is byte-for-byte reversible, and it
survives a repeated install: after installing twice and uninstalling once,
`bindings.lua`, `looknfeel.lua`, `autostart.lua`, `hyprland.lua` and
`shell.json` all compare identical to their originals.

---

## 8. Verification

```bash
# Syntax
bash -n install.sh uninstall.sh bin/nooxshell
bash -n shims/awww-omarchy-bridge shims/omarchy shims/omarchy-audio-output-volume \
        shims/omarchy-brightness-display shims/omarchy-brightness-display-ddc \
        shims/omarchy-menu shims/omarchy-menu-input shims/omarchy-menu-select \
        shims/omarchy-osd shims/omarchy-shell shims/omarchy-theme-bg-set \
        shims/omarchy-theme-bg-switcher
luac -p hypr/quickshell-islands.lua
jq . manifest.json

# Plan, without touching the system
./install.sh --dry-run

# Lifecycle
nooxshell status
nooxshell restart
nooxshell log -f

# IPC, against the live instance
nooxshell toggle menu
nooxshell toggle wifi
nooxshell toggle notifications
```

Do not lint `shims/*` with a glob: it picks up `shims/README.md`, which is
not a script, and `_omarchy-menu-shim`, which is a sourced fragment.

### Manual checks

- Every island panel renders and animates.
- The frosted X-Ray edge is visible on each panel.
- Volume and brightness keys raise the islands HUD, not the stock OSD.
- `Super+Ctrl+Space` opens the wallpaper picker and the background changes.
- `omarchy menu` opens the islands menu, and falls back to the stock menu
  when the shell is stopped.

---

## 9. Distribution

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/whonoox/quickshell/master/install.sh)
```

### How the piped install works

The installer deploys the whole shell from its own directory: the
manifest, the QML files, the shims and the CLI. A piped script has no such
directory — `BASH_SOURCE` points at a process substitution
(`/dev/fd/63`) — so the installer cannot find its own sources.

It therefore bootstraps itself:

1. Look for `manifest.json` next to the script. A checkout has one; a
   pipe does not.
2. If it is missing, clone the repository into
   `${XDG_CACHE_HOME:-~/.cache}/nooxshell/repo` and re-exec the installer
   from the clone, passing the arguments through unchanged.
3. A second run updates the cached checkout in place rather than cloning
   again.

The clone is the source of truth for `nooxshell update` and
`nooxshell uninstall` afterwards; `state.json` records its path.

`NOOXSHELL_REPO_URL`, `NOOXSHELL_REPO_REF` and `NOOXSHELL_CACHE_DIR`
override the repository, the ref and the cache location.

Pin to a release tag rather than `master` for anything reproducible:

```bash
NOOXSHELL_REPO_REF=v1.0.0 bash <(curl -fsSL https://raw.githubusercontent.com/whonoox/quickshell/v1.0.0/install.sh)
```

The installer is idempotent: re-running it replaces the Hyprland block
instead of appending a second one, and backs up the state before each run.

---

## 10. Out of Scope

These live outside the repository and are not deployed by the installer:

- `~/.config/omarchy/plugins/nuux.menu` and `nuux.lock` — Omarchy shell
  plugins, not part of the islands config.
- `~/.config/omarchy/extensions/omarchy-menu.jsonc` and `menu.sh` — user
  menu extensions.
- `~/.local/state/omarchy/current/theme/colors.toml` — Omarchy's live theme,
  read reactively by `Theme.qml`.

A fresh install on another machine needs the Omarchy plugins that own the
bar's menu button; the islands config alone does not provide them.
