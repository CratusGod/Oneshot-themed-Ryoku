#!/usr/bin/env bash
# Remove THE WORLD MACHINE from Ryoku and put the stock look back.
#
#   curl -fsSL https://raw.githubusercontent.com/CratusGod/Oneshot-themed-Ryoku/main/uninstall.sh | bash
#
# Parts: --lock --reload --boot (none given = all three)
# Flags: --yes, --dry-run
set -euo pipefail

THEME=world-machine
CONFIG=${XDG_CONFIG_HOME:-$HOME/.config}
DATA=${XDG_DATA_HOME:-$HOME/.local/share}
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/oneshot-ryoku

DO_LOCK=0 DO_RELOAD=0 DO_BOOT=0 YES=0 DRY=0

say()  { printf '\033[1;33m::\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;31m !!\033[0m %s\n' "$*" >&2; }
die()  { warn "$*"; exit 1; }
run()  { if [ "$DRY" = 1 ]; then printf '   would run: %s\n' "$*"; else "$@"; fi; }
ask() {
  [ "$YES" = 1 ] && return 0
  [ "$DRY" = 1 ] && { printf '   would ask: %s\n' "$1"; return 0; }
  if ! { true </dev/tty; } 2>/dev/null; then
    warn "no terminal to ask \"$1\"; skipping (pass --yes to accept)"
    return 1
  fi
  local reply
  printf '\033[1;33m ??\033[0m %s [y/N] ' "$1" >/dev/tty
  read -r reply </dev/tty || return 1
  case "$reply" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

for arg in "$@"; do
  case "$arg" in
    --lock)    DO_LOCK=1 ;;
    --reload)  DO_RELOAD=1 ;;
    --boot)    DO_BOOT=1 ;;
    --yes|-y)  YES=1 ;;
    --dry-run) DRY=1 ;;
    *) die "unknown option: $arg" ;;
  esac
done
if [ $((DO_LOCK + DO_RELOAD + DO_BOOT)) -eq 0 ]; then DO_LOCK=1 DO_RELOAD=1 DO_BOOT=1; fi
[ "$(id -u)" -ne 0 ] || die "run this as your normal user, not root"

# =============================== lock screen ================================
remove_lock() {
  say "lock screen"
  local current="" prev=clockwork/orbital
  [ -f "$CONFIG/qylock/theme" ] && current=$(cat "$CONFIG/qylock/theme")
  [ -f "$STATE/prev-lock" ] && prev=$(cat "$STATE/prev-lock")

  if [ "$current" = "$THEME" ]; then
    [ -f "$DATA/qylock/themes/$prev/Main.qml" ] || prev=clockwork/orbital
    say "switching back to $prev (asks for your password)"
    run ryoku-hub lock set "$prev"
  fi
  if [ -e "$DATA/qylock/themes/.ryostore-lock-$THEME" ] && command -v ryostore >/dev/null; then
    run ryostore remove lockscreens "$THEME"
  else
    run rm -rf "$DATA/qylock/themes/$THEME"
  fi
  run rm -f "$STATE/prev-lock"
  ok "lock theme removed"
}

# ============================== reload cover ================================
remove_reload() {
  say "shell reload cover"
  if pgrep -f -- 'qs -c hub' >/dev/null || pgrep -f -- 'quickshell -c hub' >/dev/null; then
    die "close Ryoku Settings first"
  fi

  local brand="$CONFIG/ryoku/brand.json"
  if [ -f "$brand" ]; then
    if [ "$DRY" = 1 ]; then
      printf '   would remove reloadCover from %s\n' "$brand"
    else
      python3 - "$brand" <<'PY'
import json, os, sys, tempfile
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
if data.pop("reloadCover", None) is not None:
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".brand.")
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, indent=4)
        f.write("\n")
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)
PY
    fi
  fi
  run ryoku-hub reload-cover prune
  ok "reload cover back to default"

  # Undo the fallback by hand. `ryoku reset` would re-lay the whole config tree.
  local rel=quickshell/reload-cover/assets/logo.png
  local base=/usr/share/ryoku/config/$rel
  run rm -f "$CONFIG/ryoku/user_edits/$rel"
  if [ -f "$base" ] && [ -d "$CONFIG/quickshell/reload-cover/assets" ]; then
    run install -m644 "$base" "$CONFIG/$rel"
  fi
  if [ "$DRY" != 1 ]; then
    rmdir -p "$CONFIG/ryoku/user_edits/quickshell/reload-cover/assets" 2>/dev/null || true
  fi
  ok "failed-reload wordmark back to default"
}

# =============================== boot screen ================================
remove_boot() {
  say "boot screen"
  if [ ! -e /etc/pacman.d/hooks/zz-twm-boot-logo.hook ] && [ ! -d /usr/local/share/twm-boot ]; then
    ok "not installed"; return 0
  fi
  ask "restore the stock boot screen? needs sudo and rebuilds your initramfs" \
    || { say "boot screen left as is"; return 0; }

  run sudo rm -f /etc/pacman.d/hooks/zz-twm-boot-logo.hook /usr/local/bin/twm-boot-logo
  if [ "$DRY" = 1 ] || sudo test -f /usr/local/share/twm-boot/logo.stock.png; then
    run sudo install -m644 /usr/local/share/twm-boot/logo.stock.png /usr/share/plymouth/themes/ryoku/logo.png
  else
    warn "no saved stock logo; reinstalling ryoku-desktop's copy"
    run sudo pacman -S --noconfirm ryoku-desktop
  fi
  run sudo rm -rf /usr/local/share/twm-boot
  run sudo ryoku-boot-apply
  ok "boot screen restored; you will see it on the next reboot"
}

[ "$DRY" = 1 ] && say "dry run: nothing will change"
[ "$DO_LOCK" = 1 ]   && remove_lock
[ "$DO_RELOAD" = 1 ] && remove_reload
[ "$DO_BOOT" = 1 ]   && remove_boot
say "done"
