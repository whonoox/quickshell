#!/usr/bin/env bash
# Installer for the Quickshell island desktop shell.
#
# Usage:
#   ./install.sh                 interactive install
#   ./install.sh --dry-run       show what would change, touch nothing
#   ./install.sh --yes           accept all defaults, no prompts
#   ./install.sh --skip-deps     assume dependencies are already installed
#   ./install.sh --no-start      do not start the shell afterwards
#
# One-liner install:
#   bash <(curl -fsSL https://raw.githubusercontent.com/whonoox/quickshell/master/install.sh)
#
# Every file this script touches is copied into a timestamped backup
# directory first, and the exact list is written to a manifest so
# uninstall.sh can roll back precisely.

set -euo pipefail

REPO_URL="${NOOXSHELL_REPO_URL:-https://github.com/whonoox/quickshell.git}"
REPO_REF="${NOOXSHELL_REPO_REF:-master}"
CACHE_DIR="${NOOXSHELL_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/nooxshell}"

HOME_DIR="$HOME"
CONFIG_DIR="$HOME_DIR/.config/quickshell"
HYPR_DIR="$HOME_DIR/.config/hypr"
BIN_DIR="$HOME_DIR/.local/bin"
FONT_DIR="$HOME_DIR/.local/share/fonts"
STATE_DIR="$HOME_DIR/.local/state/nooxshell"
OMARCHY_CONFIG="$HOME_DIR/.config/omarchy/shell.json"

DRY_RUN=0
ASSUME_YES=0
SKIP_DEPS=0
NO_START=0

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

# The installer deploys the shell from this directory: the manifest, the
# QML files, the shims and the CLI all live here. When the script is
# piped in rather than run from a checkout, that directory is a process
# substitution (/dev/fd/63) and holds nothing, so the repository is
# fetched first and the script re-executes from the clone.
bootstrap() {
  local script_dir
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"

  if [[ -n $script_dir && -f $script_dir/manifest.json ]]; then
    REPO_DIR="$script_dir"
    MANIFEST="$REPO_DIR/manifest.json"
    return 0
  fi

  info "No checkout found; fetching $REPO_URL"
  command -v git >/dev/null 2>&1 ||
    fail "git is required to install from a URL"

  mkdir -p "$CACHE_DIR"

  if [[ -d $CACHE_DIR/repo/.git ]]; then
    info "Updating the cached checkout"
    git -C "$CACHE_DIR/repo" fetch --depth 1 origin "$REPO_REF" ||
      fail "could not fetch $REPO_URL"
    git -C "$CACHE_DIR/repo" reset --hard "origin/$REPO_REF" ||
      fail "could not update the cached checkout"
  else
    info "Cloning into $CACHE_DIR/repo"
    git clone --depth 1 --branch "$REPO_REF" "$REPO_URL" "$CACHE_DIR/repo" ||
      fail "could not clone $REPO_URL"
  fi

  [[ -f $CACHE_DIR/repo/manifest.json ]] ||
    fail "the fetched checkout has no manifest.json"

  # Re-exec from the clone so the rest of the script runs against a real
  # directory. The arguments are passed through unchanged.
  exec bash "$CACHE_DIR/repo/install.sh" "$@"
}

REPO_DIR=""
MANIFEST=""

run() {
  if (( DRY_RUN )); then
    printf '  would run: %s\n' "$*"
    return 0
  fi
  "$@"
}

usage() {
  cat <<'USAGE'
Usage: install.sh [options]

Options:
  --dry-run     show what would change, touch nothing
  --yes, -y     accept all defaults, no prompts
  --skip-deps   assume dependencies are already installed
  --no-start    do not start the shell afterwards
  -h, --help    show this help

One-liner install:
  bash <(curl -fsSL https://raw.githubusercontent.com/whonoox/quickshell/master/install.sh)
USAGE
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

# The CLI was named "omarchy-islands" before it became "nooxshell", and
# the state directory was renamed with it. Move an existing installation's
# state across so the pristine backup — the only record of the user's
# original files — is not lost, and remove the old command so it does not
# linger on PATH.
migrate_old_state() {
  local old_state="$HOME_DIR/.local/state/omarchy-islands"
  local old_cli="$HOME_DIR/.local/bin/omarchy-islands"

  if [[ -d $old_state && ! -d $STATE_DIR ]]; then
    mv "$old_state" "$STATE_DIR"
    info "Migrated state directory to $STATE_DIR"
  elif [[ -d $old_state ]]; then
    # Both exist: keep the new one, but rescue the pristine backup if the
    # new directory does not have one yet.
    if [[ ! -f $STATE_DIR/pristine/backup_manifest.json && -f $old_state/pristine/backup_manifest.json ]]; then
      cp -a "$old_state/pristine" "$STATE_DIR/pristine"
      info "Recovered the pristine backup from $old_state"
    fi
    rm -rf "$old_state"
  fi

  if [[ -e $old_cli ]]; then
    rm -f "$old_cli"
    info "Removed the old omarchy-islands command"
  fi
}

# Keeps only the most recent per-run backups. The pristine copy is never
# pruned: it is what the uninstaller restores from.
prune_backups() {
  local keep="${OMARCHY_ISLANDS_BACKUP_KEEP:-3}"
  local root="$STATE_DIR/backups"

  [[ -d $root ]] || return 0

  local count
  count="$(find "$root" -mindepth 1 -maxdepth 1 -type d | wc -l)"
  (( count > keep )) || return 0

  local old
  while read -r old; do
    [[ -n $old ]] || continue
    rm -rf "$old"
  done < <(find "$root" -mindepth 1 -maxdepth 1 -type d | sort | head -n "$((count - keep))")

  info "Pruned old backups, keeping the $keep most recent"
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

# The brand font is personal and is not distributed with the shell. It is
# expected to be installed system-wide (or per-user) on the machines that
# have it, where fontconfig makes it visible to every application. The
# shell asks for it by family name and falls back to the system font when
# it is absent, so nothing here is required for the shell to work.
check_brand_font() {
  local family="Nuuxfont"

  # `grep -q` exits at the first match and closes the pipe, so fc-list
  # takes a SIGPIPE. Under pipefail that turns a successful match into a
  # failure, so the output is captured first and grep runs on the result.
  local installed
  installed="$(fc-list 2>/dev/null | grep -c ": $family:")"

  if (( installed > 0 )); then
    ok "Brand font '$family' is installed system-wide"
  else
    warn "Brand font '$family' is not installed; the shell will use the system font"
    warn "  install it with: sudo install -Dm644 Nuuxfont-Regular.ttf /usr/share/fonts/NuuXFont/ && fc-cache -f"
  fi
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
    # Remove any previous hl.layer_rule block that matched the island
    # namespaces, together with the blank and comment lines above it.
    # Matching the rule itself rather than one specific comment means a
    # user's own wording cannot leave a duplicate blur behind.
    #
    # The body is matched non-greedily across newlines: the namespace
    # pattern is itself a regex containing braces and parentheses, so it
    # cannot be described by counting braces.
    #
    # The pattern is written on one line on purpose. In perl's extended
    # mode (/x) the whitespace is stripped, which would break the literal
    # spaces around the "="; without /x, a pattern broken across lines
    # would match those newlines literally and never match.
    perl -0pi -e 's{\n(?:[ \t]*(?:--[^\n]*)?\n)*hl\.layer_rule\(\{.*?namespace\s*=\s*"[^"]*(?:-panel-main|quickshell-omarchy-menu|scoop-v2-inspector|notification-panel-main)[^"]*".*?\}\)\n}{}gs' "$looknfeel"
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

  # The CLI is the one file a user is likely to have edited in the
  # repository and then run from ~/.local/bin without reinstalling. Say so
  # when the deployed copy is out of date, so a fix that appears to have no
  # effect is explained.
  if [[ -f $dest ]] && ! cmp -s "$REPO_DIR/$src" "$dest"; then
    warn "$dest is out of date; updating it"
  fi

  if (( DRY_RUN )); then
    printf '  would install: %s\n' "$dest"
    return 0
  fi

  backup_file "$dest"
  mkdir -p "$(dirname "$dest")"
  install -Dm"$mode" "$REPO_DIR/$src" "$dest"
  ok "Installed nooxshell CLI"
}

check_path_order() {
  # The greps below exit 1 when a path is not in PATH, which under set -e
  # would abort the install. An explicit "|| true" keeps that from
  # happening; the results are checked explicitly below.
  local bin_dir
  bin_dir="$(printf '%s' "$PATH" | tr ':' '\n' | grep -n -x "$BIN_DIR" | head -1 | cut -d: -f1 || true)"

  if [[ -z $bin_dir ]]; then
    warn "$BIN_DIR is not in PATH; add it to your shell profile"
    return 0
  fi

  local usr_bin
  usr_bin="$(printf '%s' "$PATH" | tr ':' '\n' | grep -n -x "/usr/bin" | head -1 | cut -d: -f1 || true)"
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
    --arg name "$(manifest_get '.name')" \
    --arg version "$(manifest_get '.version')" \
    --arg installed_at "$(date -Iseconds)" \
    --arg repo "$REPO_DIR" \
    --arg config "$CONFIG_DIR" \
    --arg hypr_module "$(expand_path "$(manifest_get '.hypr.module.dest')")" \
    --arg hypr_require "$(expand_path "$(manifest_get '.hypr.require.file')")" \
    --arg omarchy_config "$OMARCHY_CONFIG" \
    '{
       name: $name,
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
      --no-start)
        # Do not start or restart the shell. Used by test installs that
        # point HOME at a scratch directory: a shell started there would
        # run with the wrong theme and keep drawing panels over the real
        # desktop.
        NO_START=1
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        fail "unknown option: $1"
        ;;
    esac
  done

  # A piped script has no checkout next to it, so fetch one and re-exec
  # from there. The remaining arguments are passed through unchanged.
  bootstrap "$@"

  [[ -f $MANIFEST ]] || fail "manifest not found: $MANIFEST"
  require_tools

  if (( DRY_RUN )); then
    info "Dry run: no changes will be made"
  else
    migrate_old_state
    mkdir -p "$STATE_DIR"
    BACKUP_DIR="$STATE_DIR/backups/$(date +%Y%m%d-%H%M%S)"
    PRISTINE_DIR="$STATE_DIR/pristine"
    mkdir -p "$BACKUP_DIR/files" "$PRISTINE_DIR/files"
    : >"$BACKUP_DIR/backup_manifest.json"
    [[ -f $PRISTINE_DIR/backup_manifest.json ]] || : >"$PRISTINE_DIR/backup_manifest.json"
    info "Backup directory: $BACKUP_DIR"
    prune_backups
  fi

  check_dependencies
  install_files
  install_shims
  check_brand_font
  install_hypr
  deconflict_hypr
  configure_omarchy
  install_cli
  check_path_order
  write_state

  # The manifest declares the activation hooks; they are run from there so
  # the manifest stays the single source of truth.
  local hook
  while IFS= read -r hook; do
    [[ -n $hook ]] || continue
    # A hook that starts the shell is skipped under --no-start.
    if (( NO_START )) && [[ $hook == *"nooxshell restart"* || $hook == *"nooxshell start"* ]]; then
      info "Skipping hook (--no-start): $hook"
      continue
    fi
    info "Running hook: $hook"
    # The hook targets the config that was just installed, not whatever
    # $HOME resolves to. Without this, an install pointed at a scratch
    # directory would start a shell against the wrong tree.
    run env OMARCHY_ISLANDS_QS_PATH="$CONFIG_DIR" bash -c "$hook" || warn "hook failed: $hook"
  done < <(manifest_list '.hooks.post_install')

  if (( DRY_RUN )); then
    info "Dry run complete"
    return 0
  fi

  verify

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
  nooxshell status | log -f | restart | toggle menu
SUMMARY
}

main "$@"
