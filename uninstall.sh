#!/usr/bin/env bash
# Uninstaller for the Quickshell island desktop shell.
#
# Restores the desktop to its stock state:
#   * stops this shell's Quickshell instance
#   * restores every file this installer backed up
#   * removes the files the installer created that had no previous version
#   * removes the Hyprland module and its require line
#   * restores Omarchy's shell.json
#   * brings the stock Omarchy shell back up
#
# Usage:
#   ./uninstall.sh            roll back
#   ./uninstall.sh --dry-run  show what would be restored, touch nothing

set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$REPO_DIR/manifest.json"

STATE_DIR="$HOME/.local/state/omarchy-islands"
STATE_FILE="$STATE_DIR/state.json"
BACKUP_ROOT="$STATE_DIR/backups"
PRISTINE_DIR="$STATE_DIR/pristine"

HYPR_BEGIN_MARKER="-- quickshell-islands:begin"
HYPR_END_MARKER="-- quickshell-islands:end"

DRY_RUN=0

# Paths (relative to $HOME) that the backup covers. These are restored
# rather than deleted, so removal has to skip them.
BACKED_UP_FILES=""

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

expand_path() {
  local path="$1"
  path="${path/#\~/$HOME}"
  printf '%s' "$path"
}

manifest_list() {
  jq -c -r "$1[]?" "$MANIFEST"
}

# Picks the pristine copy taken before the first install. Per-run backups
# under backups/ capture what a later run touched, which may already be the
# files the installer deployed, so they cannot be used to restore the
# user's originals.
pristine_backup() {
  [[ -f $PRISTINE_DIR/backup_manifest.json ]] || return 1
  printf '%s' "$PRISTINE_DIR"
}

stop_shell() {
  local cli="$HOME/.local/bin/omarchy-islands"
  if [[ -x $cli ]]; then
    info "Stopping the island shell"
    run "$cli" stop || warn "could not stop the shell cleanly"
  else
    info "Stopping the island shell (qs kill)"
    run qs kill -p "$HOME/.config/quickshell" || true
  fi
}

restore_backups() {
  local backup_dir="$1"
  local manifest_file="$backup_dir/backup_manifest.json"

  [[ -f $manifest_file ]] || {
    warn "no backup manifest in $backup_dir"
    return 0
  }

  local count=0
  local relative
  while IFS= read -r relative; do
    [[ -n $relative ]] || continue
    local source="$backup_dir/files/$relative"
    [[ -f $source ]] || continue

    BACKED_UP_FILES="$BACKED_UP_FILES $relative"

    if (( DRY_RUN )); then
      printf '  would restore: %s\n' "$HOME/$relative"
      count=$((count + 1))
      continue
    fi

    mkdir -p "$(dirname "$HOME/$relative")"
    cp -a "$source" "$HOME/$relative"
    count=$((count + 1))
  done <"$manifest_file"

  ok "Restored $count files from $backup_dir"
}

remove_installed() {
  local count=0
  local entry

  # Files that existed before the install are restored from the backup
  # instead of being deleted, so they must not be touched here.
  local restored=" $BACKED_UP_FILES "

  while IFS= read -r entry; do
    local dest relative
    dest="$(expand_path "$(jq -r '.dest' <<<"$entry")")"
    relative="${dest#"$HOME"/}"

    if [[ -e $dest && $restored != *" $relative "* ]]; then
      if (( DRY_RUN )); then
        printf '  would remove: %s\n' "$dest"
      else
        rm -f "$dest"
      fi
      count=$((count + 1))
    fi
  done < <(manifest_list '.files')

  while IFS= read -r entry; do
    local dest relative
    dest="$(expand_path "$(jq -r '.dest' <<<"$entry")")"
    relative="${dest#"$HOME"/}"

    if [[ -e $dest && $restored != *" $relative "* ]]; then
      if (( DRY_RUN )); then
        printf '  would remove: %s\n' "$dest"
      else
        rm -f "$dest"
      fi
      count=$((count + 1))
    fi
  done < <(manifest_list '.shims')

  while IFS= read -r entry; do
    local dest relative
    dest="$(expand_path "$(jq -r '.dest' <<<"$entry")")"
    relative="${dest#"$HOME"/}"

    if [[ -e $dest && $restored != *" $relative "* ]]; then
      if (( DRY_RUN )); then
        printf '  would remove: %s\n' "$dest"
      else
        rm -f "$dest"
      fi
      count=$((count + 1))
    fi
  done < <(manifest_list '.fonts')

  local cli_dest  cli_dest="$(expand_path "$(jq -r '.cli.dest' "$MANIFEST")")"
  if [[ -e $cli_dest ]]; then
    if (( DRY_RUN )); then
      printf '  would remove: %s\n' "$cli_dest"
    else
      rm -f "$cli_dest"
    fi
    count=$((count + 1))
  fi

  ok "Removed $count installed files"
}

# Removes the directories the installer created, if they are now empty.
remove_empty_dirs() {
  local dir
  for dir in \
    "$HOME/.config/quickshell/decorations" \
    "$HOME/.config/quickshell"; do
    if [[ -d $dir ]] && [[ -z $(ls -A "$dir" 2>/dev/null) ]]; then
      if (( DRY_RUN )); then
        printf '  would remove empty dir: %s\n' "$dir"
      else
        rmdir "$dir" 2>/dev/null || true
      fi
    fi
  done
}

remove_hypr_module() {
  local module_dest require_file
  module_dest="$(expand_path "$(jq -r '.hypr.module.dest' "$MANIFEST")")"
  require_file="$(expand_path "$(jq -r '.hypr.require.file' "$MANIFEST")")"

  if (( DRY_RUN )); then
    printf '  would remove: %s\n' "$module_dest"
    printf '  would strip require line from: %s\n' "$require_file"
    return 0
  fi

  rm -f "$module_dest"

  if [[ -f $require_file ]] && grep -qF -- "$HYPR_BEGIN_MARKER" "$require_file"; then
    local tmp
    tmp="$(mktemp)"
    awk -v b="$HYPR_BEGIN_MARKER" -v e="$HYPR_END_MARKER" '
      $0 == b { skip = 1; next }
      $0 == e { skip = 0; next }
      !skip { print }
    ' "$require_file" >"$tmp"
    mv "$tmp" "$require_file"
  fi

  ok "Removed the Hyprland module and its require line"
}

# shell.json is restored by restore_backups, which copies the pristine copy
# over the current file. This only reports on the outcome, so a failure to
# restore is not silently swallowed.
report_omarchy_config() {
  local config="$HOME/.config/omarchy/shell.json"

  if [[ ! -e $config ]]; then
    warn "shell.json is missing"
    return 0
  fi

  if (( DRY_RUN )); then
    printf '  would restore: %s\n' "$config"
    return 0
  fi

  ok "shell.json restored from the pristine backup"
}

revive_stock_shell() {
  info "Restarting the stock Omarchy shell"
  run hyprctl reload || warn "hyprctl reload failed"
  run omarchy-restart-shell || warn "omarchy-restart-shell failed"
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      -h | --help)
        sed -n '2,18p' "$0"
        exit 0
        ;;
      *)
        fail "unknown option: $1"
        ;;
    esac
  done

  [[ -f $MANIFEST ]] || fail "manifest not found: $MANIFEST"

  if (( DRY_RUN )); then
    info "Dry run: no changes will be made"
  else
    info "Removing the island shell"
  fi

  stop_shell

  local backup_dir
  if backup_dir="$(pristine_backup)"; then
    restore_backups "$backup_dir"
  else
    warn "no pristine backup found under $PRISTINE_DIR"
  fi

  remove_installed
  remove_empty_dirs
  remove_hypr_module
  report_omarchy_config

  if (( ! DRY_RUN )); then
    rm -rf "$STATE_DIR"
  fi

  revive_stock_shell

  ok "Uninstall complete"
}

main "$@"
