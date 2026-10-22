# Shims

These are the command interceptors that route Omarchy's commands at this
config's own Quickshell islands instead of the ones shipped in
`/usr/share/omarchy/shell`.

Two Quickshell instances run side by side. Anything that reaches the shell
over IPC has to name this config explicitly, or it opens the stock UI and the
two appear to disagree.

`install.sh` deploys all of them; see `../manifest.json` for the list and
modes.

## Install

```sh
install -Dm755 shims/omarchy                       ~/.local/bin/omarchy
install -Dm755 shims/omarchy-shell                 ~/.local/bin/omarchy-shell
install -Dm755 shims/omarchy-osd                   ~/.local/bin/omarchy-osd
install -Dm755 shims/omarchy-menu                  ~/.local/bin/omarchy-menu
install -Dm755 shims/omarchy-menu-select           ~/.local/bin/omarchy-menu-select
install -Dm755 shims/omarchy-menu-input            ~/.local/bin/omarchy-menu-input
install -Dm644 shims/_omarchy-menu-shim            ~/.local/bin/_omarchy-menu-shim
install -Dm755 shims/omarchy-audio-output-volume  ~/.local/bin/omarchy-audio-output-volume
install -Dm755 shims/omarchy-brightness-display   ~/.local/bin/omarchy-brightness-display
install -Dm755 shims/omarchy-brightness-display-ddc ~/.local/bin/omarchy-brightness-display-ddc
install -Dm755 shims/awww-omarchy-bridge           ~/.local/bin/awww-omarchy-bridge
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

`omarchy-shell` — intercepts the OSD show/hide calls that hardware media keys
and daemons emit, parsing the payload to summon `AudioBar` or `BrightnessBar`
instead of the stock on-screen display.

`omarchy-osd` — the same interception for the dedicated OSD entry point.

`omarchy-audio-output-volume` — applies the volume change with `pactl`
against the active physical sink, then opens and refreshes the audio HUD.

`omarchy-brightness-display` / `omarchy-brightness-display-ddc` — apply the
backlight step via `brightnessctl` or DDC/CI, then open the brightness HUD.

`awww-omarchy-bridge` — a small daemon that keeps the `awww` wallpaper layer
in sync with Omarchy's background state, including changes made by any
switcher. It records its pid in
`~/.local/state/nooxshell/awww-bridge.pid` so a second one is not started.

## The theme is left to Omarchy

The theme commands are **not** shadowed. `omarchy-theme-bg-set`,
`omarchy-theme-bg-switcher` and `omarchy-theme-switcher` are Omarchy's own,
so the stock switcher behaves exactly as it always did.

The wallpaper is drawn by awww rather than by Omarchy's background plugin,
so the bridge follows Omarchy's background symlink and redraws the
wallpaper when it changes. The `omarchy-shell` shim forwards a theme
change to this shell as well, so the islands follow the theme.

## Behaviour

Each shim checks that our instance answers (`ping`) and falls back to the
packaged command when it does not, so a stopped shell degrades into the stock
menu rather than a dead command. `MENU_QS_PATH`, `MENU_IPC_TIMEOUT` and
`MENU_QS_TARGET` in `_omarchy-menu-shim` tune the target and timeout.

The select and input shims block on a done-file the menu writes once the
request resolves, then print the selection — which is what makes
`omarchy-menu-input` usable from scripts.

## Layout

The shims must be installed flat into one directory: `omarchy` locates
`omarchy-menu` beside itself, and the rest source `_omarchy-menu-shim` from
their own directory.
