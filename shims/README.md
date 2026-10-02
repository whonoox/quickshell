# Menu shims

These route Omarchy's menu commands at this config's own Quickshell menu
(`OmarchyMenu.qml`) instead of the one shipped in `/usr/share/omarchy/shell`.

Two Quickshell instances run side by side. Anything that reaches the menu over
IPC has to name this config explicitly, or it opens the stock menu and the two
appear to disagree.

## Install

```sh
install -Dm755 shims/omarchy              ~/.local/bin/omarchy
install -Dm755 shims/omarchy-menu         ~/.local/bin/omarchy-menu
install -Dm755 shims/omarchy-menu-select  ~/.local/bin/omarchy-menu-select
install -Dm755 shims/omarchy-menu-input   ~/.local/bin/omarchy-menu-input
install -Dm644 shims/_omarchy-menu-shim   ~/.local/bin/_omarchy-menu-shim
```

`~/.local/bin` must precede `/usr/bin` in `PATH`. `_omarchy-menu-shim` is
sourced rather than executed, hence mode 644.

## Why each one exists

`omarchy-menu*` — direct entry points. The packaged copies summon the stock
menu; these summon ours.

`omarchy` — a pass-through. `/usr/bin/omarchy` derives `OMARCHY_BIN_DIR` from
its own location, so `omarchy menu ...` resolves to `/usr/bin/omarchy-menu` and
bypasses the shims above, which would make `omarchy menu` and `omarchy-menu`
open different menus. This wrapper re-routes only the `menu` group and hands
every other subcommand to the packaged binary untouched.

## Behaviour

Each shim checks that our instance answers (`ping`) and falls back to the
packaged command when it does not, so a stopped shell degrades into the stock
menu rather than a dead command. `MENU_QS_PATH`, `MENU_IPC_TIMEOUT` and
`MENU_QS_TARGET` in `_omarchy-menu-shim` tune the target and timeout.

The select and input shims block on a done-file the menu writes once the
request resolves, then print the selection — which is what makes
`omarchy-menu-input` usable from scripts.

## Caveat

`omarchy` execs `$HOME/.local/bin/omarchy-menu` by absolute path rather than
resolving it relative to itself like the other shims do. It is correct for a
`~/.local/bin` install and breaks only if these are installed somewhere else.
