#!/usr/bin/env bash
# Installer for the Quickshell island desktop shell.
#
# Usage:
#   ./install.sh                 interactive install
#   ./install.sh --dry-run       show what would change, touch nothing
#   ./install.sh --yes           accept all defaults, no prompts
#   ./install.sh --skip-deps     assume dependencies are already installed
#
# Every file this script touches is copied into a timestamped backup
# directory first, and the exact list is written to a manifest so
# uninstall.sh can roll back precisely.

set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$REPO_DIR/manifest.json"

HOME_DIR="$HOME"
CONFIG_DIR="$HOME_DIR/.config/quickshell"
HYPR_DIR="$HOME_DIR/.config/hypr"
BIN_DIR="$HOME_DIR/.local/bin"
FONT_DIR="$HOME_DIR/.local/share/fonts"
STATE_DIR="$HOME_DIR/.local/state/omarchy-islands"
OMARCHY_CONFIG="$HOME_DIR/.config/omarchy/shell.json"

DRY_RUN=0
ASSUME_YES=0
SKIP_DEPS=0

# Per-run backup of everything touched, plus a one-time pristine copy of the
# files that existed before the first install.
BACKUP_DIR=""
PRISTINE_DIR=""

# Marker used to fence the block this installer owns inside hyprland.lua.
HYPR_BEGIN_MARKER="-- quickshell-islands:begin"
HYPR_END_MARKER="-- quickshell-islands:end"

info() { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m::\033[0m %s\n' "$*" >&2; }
fail() {
  printf '\033[1;31m::\033[0m %s\n' "$*" >&2
  exit 1
}
ok() { printf '\033[1;32m::\033[0m %s\n' "$*"; }

run() {
  if (( DRY_RUN )); then
    printf '  would run: %s\n' "$*"
    return 0
  fi
  "$@"
}

confirm() {
  (( ASSUME_YES )) && return 0
  (( DRY_RUN )) && return 0
  local reply
  read -r -p "$1 [y/N] " reply
  [[ $reply == "y" || $reply == "Y" ]]
}

expand_path() {
  local path="$1"
  path="${path/#\~/$HOME_DIR}"
  printf '%s' "$path"
}

# Reads a dotted path out of the manifest.
manifest_get() {
  jq -r "$1 // empty" "$MANIFEST"
}

manifest_list() {
  jq -c -r "$1[]?" "$MANIFEST"
}

require_tools() {
  local missing=()
  local tool
  for tool in jq git; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done
  (( ${#missing[@]} == 0 )) || fail "missing required tools: ${missing[*]}"
}

check_dependencies() {
  (( SKIP_DEPS )) && {
    info "Skipping dependency check"
    return 0
  }

  local packages
  packages="$(manifest_list '.dependencies.pacman')"
  [[ -n $packages ]] || return 0

  local missing=()
  local package
  for package in $packages; do
    pacman -Q "$package" >/dev/null 2>&1 || missing+=("$package")
  done

  if (( ${#missing[@]} == 0 )); then
    ok "All dependencies installed"
    return 0
  fi

  warn "Missing packages: ${missing[*]}"

  if ! command -v pacman >/dev/null 2>&1; then
    fail "pacman is required to install: ${missing[*]}"
  fi

  if ! confirm "Install missing packages with sudo pacman -S --needed?"; then
    fail "Install the missing packages first, then re-run: ${missing[*]}"
  fi

  # A non-interactive sudo (as in `curl | bash`) has no terminal to prompt on,
  # so ask for the password up front and let paclock read it from the tty.
  if (( ! DRY_RUN )); then
    if [[ -t 0 ]]; then
      sudo -v || fail "sudo authentication failed"
    else
      fail "Cannot install packages without an interactive terminal. Run: sudo pacman -S --needed ${missing[*]}"
    fi
    sudo pacman -S --needed --noconfirm "${missing[@]}" || fail "pacman failed"
  else
    printf '  would run: sudo pacman -S --needed %s\n' "${missing[*]}"
  fi
}

backup_file() {
  local path="$1"
  (( DRY_RUN )) && return 0
  [[ -e $path ]] || return 0

  local relative="${path#$HOME_DIR/}"

  # The pristine copy is written once and never overwritten. A second
  # install would otherwise capture the files the first install already
  # deployed, and the uninstaller would then restore our own copies instead
  # of the user's originals.
  if [[ ! -e $PRISTINE_DIR/files/$relative ]]; then
    mkdir -p "$(dirname "$PRISTINE_DIR/files/$relative")"
    cp -a "$path" "$PRISTINE_DIR/files/$relative"
    printf '%s\n' "$relative" >>"$PRISTINE_DIR/backup_manifest.json"
  fi

  # Every run also gets its own timestamped snapshot of what it touched.
  mkdir -p "$BACKUP_DIR/files/$(dirname "$relative")"
  cp -a "$path" "$BACKUP_DIR/files/$relative"
  printf '%s\n' "$relative" >>"$BACKUP_DIR/backup_manifest.json"
}

install_files() {
  local entry
  local count=0

  while IFS= read -r entry; do
    local src dest
    src="$(jq -r '.src' <<<"$entry")"
    dest="$(expand_path "$(jq -r '.dest' <<<"$entry")")"

    [[ -f $REPO_DIR/$src ]] || fail "manifest source missing: $src"

    if (( DRY_RUN )); then
      printf '  would install: %s\n' "$dest"
      count=$((count + 1))
      continue
    fi

    backup_file "$dest"

    # When the repo is itself the config directory, source and destination
    # are the same file; copying it onto itself is an error.
    if [[ $(readlink -f "$REPO_DIR/$src") == $(readlink -f "$dest") ]]; then
      count=$((count + 1))
      continue
    fi

    mkdir -p "$(dirname "$dest")"
    cp -a "$REPO_DIR/$src" "$dest"
    count=$((count + 1))
  done < <(manifest_list '.files')

  ok "Installed $count shell files"
}

install_shims() {
  local entry
  local count=0

  while IFS= read -r entry; do
    local src dest mode
    src="$(jq -r '.src' <<<"$entry")"
    dest="$(expand_path "$(jq -r '.dest' <<<"$entry")")"
    mode="$(jq -r '.mode' <<<"$entry")"

    [[ -f $REPO_DIR/$src ]] || fail "manifest source missing: $src"

    if (( DRY_RUN )); then
      printf '  would install: %s (mode %s)\n' "$dest" "$mode"
      count=$((count + 1))
      continue
    fi

    backup_file "$dest"
    mkdir -p "$(dirname "$dest")"
    install -Dm"$mode" "$REPO_DIR/$src" "$dest"
    count=$((count + 1))
  done < <(manifest_list '.shims')

  ok "Installed $count shims"
}

install_fonts() {
  local entry
  local count=0

  while IFS= read -r entry; do
    local src dest mode
    src="$(jq -r '.src' <<<"$entry")"
    dest="$(expand_path "$(jq -r '.dest' <<<"$entry")")"
    mode="$(jq -r '.mode // "0644"' <<<"$entry")"

    [[ -f $REPO_DIR/$src ]] || fail "manifest source missing: $src"

    if (( DRY_RUN )); then
      printf '  would install: %s\n' "$dest"
      count=$((count + 1))
      continue
    fi

    backup_file "$dest"
    mkdir -p "$(dirname "$dest")"
    install -Dm"$mode" "$REPO_DIR/$src" "$dest"
    count=$((count + 1))
  done < <(manifest_list '.fonts')

  (( count > 0 )) && run fc-cache -f "$FONT_DIR"
  ok "Installed $count fonts"
}

# Installs the Hyprland module and the single require line that loads it.
install_hypr() {
  local module_src module_dest
  module_src="$(manifest_get '.hypr.module.src')"
  module_dest="$(expand_path "$(manifest_get '.hypr.module.dest')")"
  local require_file
  require_file="$(expand_path "$(manifest_get '.hypr.require.file')")"
  local require_line
  require_line="$(manifest_get '.hypr.require.line')"

  [[ -f $REPO_DIR/$module_src ]] || fail "manifest source missing: $module_src"

  if (( DRY_RUN )); then
    printf '  would install: %s\n' "$module_dest"
    printf '  would add to %s: %s\n' "$require_file" "$require_line"
    return 0
  fi

  backup_file "$module_dest"
  backup_file "$require_file"
  mkdir -p "$(dirname "$module_dest")"
  install -Dm644 "$REPO_DIR/$module_src" "$module_dest"

  [[ -f $require_file ]] || fail "Hyprland config not found: $require_file"

  # Idempotent: remove a previously installed block, then append a fresh one.
  if grep -qF -- "$HYPR_BEGIN_MARKER" "$require_file"; then
    local tmp
    tmp="$(mktemp)"
    awk -v b="$HYPR_BEGIN_MARKER" -v e="$HYPR_END_MARKER" '
      $0 == b { skip = 1; next }
      $0 == e { skip = 0; next }
      !skip { print }
    ' "$require_file" >"$tmp"
    mv "$tmp" "$require_file"
  fi

  {
    echo ""
    echo "$HYPR_BEGIN_MARKER"
    echo "$require_line"
    echo "$HYPR_END_MARKER"
  } >>"$require_file"

  ok "Installed Hyprland module and require line"
}

# Removes the hand-written island bindings, layer rule and autostart entries
# that the module now owns, so nothing is bound or launched twice.
deconflict_hypr() {
  local bindings="$HYPR_DIR/bindings.lua"
  local looknfeel="$HYPR_DIR/looknfeel.lua"
  local autostart="$HYPR_DIR/autostart.lua"

  if (( DRY_RUN )); then
    printf '  would deconflict: %s, %s, %s\n' "$bindings" "$looknfeel" "$autostart"
    return 0
  fi

  local file
  for file in "$bindings" "$looknfeel" "$autostart"; do
    [[ -f $file ]] || continue
    backup_file "$file"
  done

  # The module owns the quickshell:* dispatches, the X-Ray layer rule and the
  # qs/awww autostart. Strip the previous hand-written equivalents.
  if [[ -f $bindings ]]; then
    sed -i \
      -e '/^hl\.unbind("SUPER + SPACE")$/d' \
      -e '/^o\.bind("SUPER + SPACE", "Omarchy menu", hl\.dsp\.global("quickshell:menuToggle"))$/d' \
      -e '/^hl\.unbind("SUPER + ALT + SPACE")$/d' \
      -e '/^o\.bind("SUPER + ALT + SPACE", "Apps menu", hl\.dsp\.global("quickshell:appsToggle"))$/d' \
      -e '/^hl\.unbind("SUPER + CTRL + W")$/d' \
      -e '/^o\.bind("SUPER + CTRL + W", "Wifi HUD and Panel", hl\.dsp\.global("quickshell:wifiToggle"))$/d' \
      -e '/^hl\.unbind("SUPER + CTRL + B")$/d' \
      -e '/^o\.bind("SUPER + CTRL + B", "Bluetooth HUD and Panel", hl\.dsp\.global("quickshell:bluetoothToggle"))$/d' \
      -e '/^hl\.unbind("SUPER + CTRL + T")$/d' \
      -e '/^o\.bind("SUPER + CTRL + T", "Time HUD and Panel", hl\.dsp\.global("quickshell:timeToggle"))$/d' \
      -e '/^hl\.unbind("SUPER + CTRL + P")$/d' \
      -e '/^o\.bind("SUPER + CTRL + P", "Power HUD and Panel", hl\.dsp\.global("quickshell:batteryToggle"))$/d' \
      -e '/^hl\.unbind("SUPER + CTRL + SPACE")$/d' \
      -e '/^o\.bind("SUPER + CTRL + SPACE", "Wallpaper switcher", hl\.dsp\.global("quickshell:wallpaperToggle"))$/d' \
      -e '/^hl\.unbind("XF86AudioRaiseVolume")$/d' \
      -e '/^o\.bind("XF86AudioRaiseVolume", "Volume up", "omarchy-audio-output-volume +10", { locked = true, repeating = true })$/d' \
      -e '/^hl\.unbind("XF86AudioLowerVolume")$/d' \
      -e '/^o\.bind("XF86AudioLowerVolume", "Volume down", "omarchy-audio-output-volume -10", { locked = true, repeating = true })$/d' \
      -e '/^hl\.unbind("XF86MonBrightnessUp")$/d' \
      -e '/^o\.bind("XF86MonBrightnessUp", "Brightness up", "omarchy-brightness-display +10%", { locked = true, repeating = true })$/d' \
      -e '/^hl\.unbind("XF86MonBrightnessDown")$/d' \
      -e '/^o\.bind("XF86MonBrightnessDown", "Brightness down", "omarchy-brightness-display 10%-", { locked = true, repeating = true })$/d' \
      "$bindings"
  fi

  if [[ -f $looknfeel ]]; then
    # Remove the previous hl.layer_rule block that matched the panel
    # namespaces, including the comment that introduced it.
    perl -0pi -e 's{\n-- Layer rules for Quickshell scoop panels.*?\n\}\)\n}{}s' "$looknfeel"
  fi

  if [[ -f $autostart ]]; then
    sed -i \
      -e '\|^o\.launch_on_start(os\.getenv("HOME") \.\. "/\.local/bin/awww-omarchy-bridge")$|d' \
      -e '/^o\.launch_on_start("qs")$/d' \
      "$autostart"
  fi

  ok "Deconflicted Hyprland bindings, layer rules and autostart"
}

# Suppresses the stock Omarchy bar and popups by disabling the plugins our
# shell replaces. Omarchy's own helper normalizes and commits shell.json.
configure_omarchy() {
  local plugins
  plugins="$(manifest_list '.omarchy.disablePlugins')"
  [[ -n $plugins ]] || return 0

  if (( DRY_RUN )); then
    printf '  would disable omarchy plugins: %s\n' "$(echo "$plugins" | tr '\n' ' ')"
    return 0
  fi

  backup_file "$OMARCHY_CONFIG"

  local helper="/usr/share/omarchy/bin/omarchy-shell-config"
  if [[ -f $helper ]]; then
    # shellcheck source=/dev/null
    source "$helper"
    # Keep the plugins Omarchy already disabled and add ours on top.
    local program="$NORMALIZE"'
      | .disabledPlugins = (((.disabledPlugins // []) | array_or_empty) + $plugins | unique)
    '
    local plugin_json
    plugin_json="$(printf '%s\n' "$plugins" | jq -R . | jq -s .)"
    if commit "$program" --argjson plugins "$plugin_json" >/dev/null; then
      ok "Configured Omarchy shell.json"
    else
      warn "could not update shell.json"
    fi
    return 0
  fi

  warn "omarchy-shell-config helper not found; skipping shell.json update"
}

install_cli() {
  local src dest mode
  src="$(manifest_get '.cli.src')"
  dest="$(expand_path "$(manifest_get '.cli.dest')")"
  mode="$(manifest_get '.cli.mode')"

  [[ -f $REPO_DIR/$src ]] || fail "manifest source missing: $src"

  if (( DRY_RUN )); then
    printf '  would install: %s\n' "$dest"
    return 0
  fi

  backup_file "$dest"
  mkdir -p "$(dirname "$dest")"
  install -Dm"$mode" "$REPO_DIR/$src" "$dest"
  ok "Installed omarchy-islands CLI"
}

check_path_order() {
  local bin_dir
  bin_dir="$(printf '%s' "$PATH" | tr ':' '\n' | grep -n -x "$BIN_DIR" | head -1 | cut -d: -f1)"

  if [[ -z $bin_dir ]]; then
    warn "$BIN_DIR is not in PATH; add it to your shell profile"
    return 0
  fi

  local usr_bin
  usr_bin="$(printf '%s' "$PATH" | tr ':' '\n' | grep -n -x "/usr/bin" | head -1 | cut -d: -f1)"
  [[ -n $usr_bin ]] || return 0

  if (( bin_dir > usr_bin )); then
    warn "$BIN_DIR comes after /usr/bin in PATH; the shims would not shadow the stock commands"
  else
    ok "$BIN_DIR precedes /usr/bin in PATH"
  fi
}

write_state() {
  (( DRY_RUN )) && return 0

  jq -n \
    --arg version "$(manifest_get '.version')" \
    --arg installed_at "$(date -Iseconds)" \
    --arg repo "$REPO_DIR" \
    --arg config "$CONFIG_DIR" \
    --arg hypr_module "$(expand_path "$(manifest_get '.hypr.module.dest')")" \
    --arg hypr_require "$(expand_path "$(manifest_get '.hypr.require.file')")" \
    --arg omarchy_config "$OMARCHY_CONFIG" \
    '{
       name: "omarchy-quickshell-islands",
       version: $version,
       installed_at: $installed_at,
       repo: $repo,
       config: $config,
       hypr_module: $hypr_module,
       hypr_require: $hypr_require,
       omarchy_config: $omarchy_config
     }' >"$STATE_DIR/state.json"

  ok "Wrote state to $STATE_DIR/state.json"
}

verify() {
  local failures=0

  local entry
  while IFS= read -r entry; do
    local src dest
    src="$(jq -r '.src' <<<"$entry")"
    dest="$(expand_path "$(jq -r '.dest' <<<"$entry")")"
    [[ -f $dest ]] || {
      warn "missing: $dest"
      failures=$((failures + 1))
    }
  done < <(manifest_list '.files')

  while IFS= read -r entry; do
    local dest mode
    dest="$(expand_path "$(jq -r '.dest' <<<"$entry")")"
    mode="$(jq -r '.mode' <<<"$entry")"
    # 0644 entries are sourced helpers, not executables.
    [[ $mode == "0644" ]] && continue
    [[ -x $dest ]] || {
      warn "not executable: $dest"
      failures=$((failures + 1))
    }
  done < <(manifest_list '.shims')

  (( failures == 0 )) || fail "$failures verification checks failed"
  ok "All manifest entries verified"
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --yes | -y)
        ASSUME_YES=1
        shift
        ;;
      --skip-deps)
        SKIP_DEPS=1
        shift
        ;;
      -h | --help)
        sed -n '2,12p' "$0"
        exit 0
        ;;
      *)
        fail "unknown option: $1"
        ;;
    esac
  done

  [[ -f $MANIFEST ]] || fail "manifest not found: $MANIFEST"
  require_tools

  if (( DRY_RUN )); then
    info "Dry run: no changes will be made"
  else
    mkdir -p "$STATE_DIR"
    BACKUP_DIR="$STATE_DIR/backups/$(date +%Y%m%d-%H%M%S)"
    PRISTINE_DIR="$STATE_DIR/pristine"
    mkdir -p "$BACKUP_DIR/files" "$PRISTINE_DIR/files"
    : >"$BACKUP_DIR/backup_manifest.json"
    [[ -f $PRISTINE_DIR/backup_manifest.json ]] || : >"$PRISTINE_DIR/backup_manifest.json"
    info "Backup directory: $BACKUP_DIR"
  fi

  check_dependencies
  install_files
  install_shims
  install_fonts
  install_hypr
  deconflict_hypr
  configure_omarchy
  install_cli
  check_path_order
  write_state

  if (( DRY_RUN )); then
    info "Dry run complete"
    return 0
  fi

  verify

  info "Reloading Hyprland"
  run hyprctl reload || warn "hyprctl reload failed"

  info "Restarting the island shell"
  run "$BIN_DIR/omarchy-islands" restart || warn "shell restart failed; start it with 'omarchy-islands start'"

  ok "Install complete"
  cat <<'SUMMARY'

Shortcuts
  Super+Space         Omarchy menu
  Super+Alt+Space     Apps menu
  Super+Ctrl+W        Wifi
  Super+Ctrl+B        Bluetooth
  Super+Ctrl+T        Time
  Super+Ctrl+P        Power
  Super+Ctrl+Space    Wallpaper picker

Management
  omarchy-islands status | log -f | restart | toggle menu
SUMMARY
}

main "$@"
