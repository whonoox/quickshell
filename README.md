# Nooxshell

A floating-island desktop shell for [Omarchy](https://omarchy.org), built on
[Quickshell](https://quickshell.org). Panels float over the stock Omarchy
desktop as single-vector "scoop" shapes with a compositor-level X-Ray blur.

Managed with the `nooxshell` command.

## Install

Needs Omarchy 4.0 or newer. Video wallpapers and background intros are
played by OWE, whose handover with the Omarchy shell came with 4.5: on
4.0.x the shell works with still wallpapers only, and the pickers skip
intros. The installer says which of the two you have.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/whonoox/quickshell/master/install.sh)
```

The installer needs the whole shell — the manifest, the QML files, the
shims — which a piped script does not carry. It fetches the repository
into `~/.cache/nooxshell/repo` on first run and works from there.

From a checkout:

```bash
./install.sh              # interactive
./install.sh --dry-run    # show what would change, touch nothing
./install.sh --yes        # accept defaults
./install.sh --theme      # also install the Nooxnpaints theme, no prompt
./install.sh --no-theme   # do not offer the theme
```

At the end, the installer offers the companion
[Nooxnpaints theme](https://github.com/whonoox/omarchy-nooxnpaints-theme),
which lives in its own repository. It is opt-in: the prompt defaults to no,
and `--yes` leaves it out. On yes, it runs
`omarchy theme install <repo>`, which clones the theme into
`~/.config/omarchy/themes/nooxnpaints` and makes it the current theme. If
the theme is already there, it is only made current with
`omarchy theme set nooxnpaints`, so local changes in it are kept. The
repository URL is set in `manifest.json` under `theme`.

The installer backs up every file it touches to
`~/.local/state/nooxshell/backups/<timestamp>/` and writes the
installed state to `~/.local/state/nooxshell/state.json`.

## Uninstall

```bash
./uninstall.sh
```

Restores every backed-up file, removes the Hyprland module and its require
line, restores `shell.json`, and brings the stock Omarchy shell back up.

## Shortcuts

| Key | Action |
| :--- | :--- |
| `Super+Space` | Omarchy menu |
| `Super+Alt+Space` | Apps menu |
| `Super+Ctrl+W` | Wi-Fi |
| `Super+Ctrl+B` | Bluetooth |
| `Super+Ctrl+T` | Time |
| `Super+Ctrl+P` | Power |
| `Super+Ctrl+Space` | Wallpaper picker |
| `Super+Shift+Ctrl+Space` | Theme picker |
| Volume / Brightness keys | Island HUDs |

## Managing the shell

```bash
nooxshell status        # instance, IPC health, available targets
nooxshell doctor        # check for stray instances and theme problems
nooxshell restart
nooxshell log -f
nooxshell toggle menu
```

Two Quickshell instances are always running: the stock Omarchy shell at
`/usr/share/omarchy/shell` and the islands at `~/.config/quickshell`. The
CLI scopes every operation to the islands instance with `qs --path`.

If every panel appears twice, once in the live theme colors and once in the
default palette, a stray instance is running. `nooxshell doctor`
identifies it and `nooxshell doctor --fix` stops it.

## Configuration

`~/.config/quickshell/config.toml` holds the user settings. Edits apply
live as soon as the file is saved.

```toml
rounding = 20                # corner radius in px for the islands, their scoops and the windows (0-20)
two_column_app_grid = true   # the apps menu two to a line; false for a single list
hide_delay = 3.5             # seconds an island stays after popping up on its own (0.5-60)
workspace_hide_factor = 0.43 # the workspace bar's wait as a fraction of hide_delay (0-1, or 0-100 as %)
```

Hyprland's window rounding follows the same value, so set it here rather
than in `looknfeel.lua`. Reinstalling keeps your copy.

## Layout

```
install.sh / uninstall.sh     one-click installer and rollback
manifest.json                 declarative deployment manifest
config.toml                   user settings (rounding, app grid, hide delays)
bin/nooxshell           management CLI
hypr/                         Hyprland bindings, layer rules, autostart
shims/                        command interceptors for ~/.local/bin
*.qml, *.js                   the shell
decorations/                  vector assets
```

## Brand font

The shell asks for the `Nuuxfont` family by name. The font is not bundled
here — it is a personal typeface, and this repository is public. Install it
system-wide on any machine that should use it:

```bash
sudo install -Dm644 Nuuxfont-Regular.ttf /usr/share/fonts/NuuXFont/
fc-cache -f
```

Without it the shell falls back to the system font and everything still
works; `nooxshell doctor` reports which font is in use.

## Documentation

- [docs/one_click_installable_shell_plan.md](docs/one_click_installable_shell_plan.md) — distribution plan and the verified facts behind it
- [QUICKSHELL_ARCHITECTURE.md](QUICKSHELL_ARCHITECTURE.md) — how the shell works internally
