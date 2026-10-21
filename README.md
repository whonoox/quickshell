# Quickshell Islands

A floating-island desktop shell for [Omarchy](https://omarchy.org), built on
[Quickshell](https://quickshell.org). Panels float over the stock Omarchy
desktop as single-vector "scoop" shapes with a compositor-level X-Ray blur.

## Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/whonoox/quickshell/master/install.sh)
```

From a checkout:

```bash
./install.sh              # interactive
./install.sh --dry-run    # show what would change, touch nothing
./install.sh --yes        # accept defaults
```

The installer backs up every file it touches to
`~/.local/state/omarchy-islands/backups/<timestamp>/` and writes the
installed state to `~/.local/state/omarchy-islands/state.json`.

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
| Volume / Brightness keys | Island HUDs |

## Managing the shell

```bash
omarchy-islands status        # instance, IPC health, available targets
omarchy-islands doctor        # check for stray instances and theme problems
omarchy-islands restart
omarchy-islands log -f
omarchy-islands toggle menu
```

Two Quickshell instances are always running: the stock Omarchy shell at
`/usr/share/omarchy/shell` and the islands at `~/.config/quickshell`. The
CLI scopes every operation to the islands instance with `qs --path`.

If every panel appears twice, once in the live theme colors and once in the
default palette, a stray instance is running. `omarchy-islands doctor`
identifies it and `omarchy-islands doctor --fix` stops it.

## Layout

```
install.sh / uninstall.sh     one-click installer and rollback
manifest.json                 declarative deployment manifest
bin/omarchy-islands           management CLI
hypr/                         Hyprland bindings, layer rules, autostart
shims/                        command interceptors for ~/.local/bin
fonts/                        brand font, loaded in-shell
*.qml, *.js                   the shell
decorations/                  vector assets
```

## Documentation

- [docs/one_click_installable_shell_plan.md](docs/one_click_installable_shell_plan.md) — distribution plan and the verified facts behind it
- [QUICKSHELL_ARCHITECTURE.md](QUICKSHELL_ARCHITECTURE.md) — how the shell works internally
