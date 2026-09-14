#!/usr/bin/env bash
# THE WORLD MACHINE for Ryoku: lock screen, shell reload cover, boot screen.
#
#   curl -fsSL https://raw.githubusercontent.com/CratusGod/Oneshot-themed-Ryoku/main/install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- --lock --dry-run
#
# Parts: --lock --reload --boot (none given = all three)
# Flags: --yes (answer yes to every question), --dry-run (print, change nothing)
set -euo pipefail

REPO=${ONESHOT_REPO:-CratusGod/Oneshot-themed-Ryoku}
REF=${ONESHOT_REF:-main}
THEME=world-machine

CONFIG=${XDG_CONFIG_HOME:-$HOME/.config}
DATA=${XDG_DATA_HOME:-$HOME/.local/share}
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/oneshot-ryoku

DO_LOCK=0 DO_RELOAD=0 DO_BOOT=0 YES=0 DRY=0

say()  { printf '\033[1;33m::\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;31m !!\033[0m %s\n' "$*" >&2; }
die()  { warn "$*"; exit 1; }

# run a command, or only show it in --dry-run
run() {
  if [ "$DRY" = 1 ]; then printf '   would run: %s\n' "$*"; else "$@"; fi
}

# yes/no question; stdin is the curl pipe, so read the terminal directly
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
    -h|--help) sed -n '2,9p' "$0" 2>/dev/null || true; exit 0 ;;
    *) die "unknown option: $arg" ;;
  esac
done
if [ $((DO_LOCK + DO_RELOAD + DO_BOOT)) -eq 0 ]; then DO_LOCK=1 DO_RELOAD=1 DO_BOOT=1; fi

[ "$(id -u)" -ne 0 ] || die "run this as your normal user, not root; it asks for sudo when it needs it"
command -v ryoku-hub >/dev/null || die "ryoku-hub not found; this installer is for Ryoku"
command -v python3   >/dev/null || die "python3 is required"

# ---- get the files: use this checkout if run from one, otherwise download ----
SRC=""
here=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)
if [ -n "$here" ] && [ -f "$here/lockscreen/$THEME/Main.qml" ]; then
  SRC=$here
else
  command -v curl >/dev/null || die "curl is required"
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  say "downloading $REPO@$REF"
  curl -fsSL "https://codeload.github.com/$REPO/tar.gz/$REF" | tar -xz -C "$TMP" --strip-components=1 \
    || die "download failed"
  SRC=$TMP
fi

mkdir -p "$STATE" 2>/dev/null || true

# =============================== lock screen ================================
install_lock() {
  say "lock screen"
  local themes="$DATA/qylock/themes"
  [ -d "$themes" ] || die "no qylock themes folder at $themes; is the Ryoku lock screen installed?"

  local current=""
  [ -f "$CONFIG/qylock/theme" ] && current=$(cat "$CONFIG/qylock/theme")
  if [ -n "$current" ] && [ "$current" != "$THEME" ] && [ ! -f "$STATE/prev-lock" ]; then
    [ "$DRY" = 1 ] || printf '%s\n' "$current" >"$STATE/prev-lock"
  fi

  run rm -rf "$themes/$THEME.new"
  run cp -a "$SRC/lockscreen/$THEME" "$themes/$THEME.new"
  run rm -rf "$themes/$THEME"
  run mv "$themes/$THEME.new" "$themes/$THEME"
  ok "theme copied to $themes/$THEME"

  if [ "$current" = "$THEME" ]; then
    ok "already your active theme"
    if ask "refresh the login screen copy too (asks for your password)?"; then
      run ryoku-hub lock set "$THEME"
    fi
  elif ask "use it now for the lock screen and login screen (asks for your password)?"; then
    run ryoku-hub lock set "$THEME"
    ok "active"
  else
    say "pick it later in Ryoku Settings > Lockscreen"
  fi
}

# ============================== reload cover ================================
install_reload() {
  say "shell reload cover"
  if pgrep -f -- 'qs -c hub' >/dev/null || pgrep -f -- 'quickshell -c hub' >/dev/null; then
    die "close Ryoku Settings first; saving there would undo this change"
  fi

  local brand="$CONFIG/ryoku/brand.json"
  local desc
  if [ "$DRY" = 1 ]; then
    printf '   would run: ryoku-hub reload-cover import %s\n' "$SRC/reload/cover.png"
    desc='{"path":"<managed>","name":"cover.png","kind":"image","bytes":0}'
  else
    desc=$(ryoku-hub reload-cover import "$SRC/reload/cover.png") || die "reload-cover import failed"
  fi

  # Settings is the normal writer of brand.json; add only the reloadCover key and
  # keep every other key exactly as it is.
  if [ "$DRY" = 1 ]; then
    printf '   would set reloadCover in %s\n' "$brand"
  else
    mkdir -p "$(dirname "$brand")"
    [ -f "$brand" ] && [ ! -f "$STATE/brand.json.bak" ] && cp "$brand" "$STATE/brand.json.bak"
    DESC="$desc" python3 - "$brand" <<'PY'
import json, os, sys, tempfile
path = sys.argv[1]
data = {}
if os.path.exists(path):
    with open(path) as f:
        data = json.load(f)
cover = json.loads(os.environ["DESC"])
cover["enabled"] = True
data["reloadCover"] = cover
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".brand.")
with os.fdopen(fd, "w") as f:
    json.dump(data, f, indent=4)
    f.write("\n")
os.chmod(tmp, 0o644)
os.replace(tmp, path)
PY
  fi
  ok "reload cover set"

  # Failed-reload fallback. The overlay copy is what survives updates; the live
  # copy makes it show now.
  local rel=quickshell/reload-cover/assets/logo.png
  run install -Dm644 "$SRC/reload/fallback.png" "$CONFIG/ryoku/user_edits/$rel"
  if [ -d "$CONFIG/quickshell/reload-cover/assets" ]; then
    run install -m644 "$SRC/reload/fallback.png" "$CONFIG/$rel"
  fi
  ok "failed-reload wordmark set"
}

# =============================== boot screen ================================
install_boot() {
  say "boot screen"
  local theme=/usr/share/plymouth/themes/ryoku
  [ -f "$theme/logo.png" ] || { warn "no Ryoku Plymouth theme at $theme; skipping boot screen"; return 0; }
  command -v ryoku-boot-apply >/dev/null || { warn "ryoku-boot-apply not found; skipping boot screen"; return 0; }

  ask "change the boot screen? needs sudo and rebuilds your initramfs (about a minute)" \
    || { say "boot screen skipped"; return 0; }

  run sudo install -d -m755 /usr/local/share/twm-boot
  # keep Ryoku's own logo once, so uninstall never needs the package
  if [ "$DRY" = 1 ] || ! sudo test -f /usr/local/share/twm-boot/logo.stock.png; then
    run sudo install -m644 "$theme/logo.png" /usr/local/share/twm-boot/logo.stock.png
  fi
  run sudo install -m644 "$SRC/boot/logo.png" /usr/local/share/twm-boot/logo.png
  run sudo install -Dm755 "$SRC/boot/twm-boot-logo" /usr/local/bin/twm-boot-logo
  run sudo install -Dm644 "$SRC/boot/zz-twm-boot-logo.hook" /etc/pacman.d/hooks/zz-twm-boot-logo.hook
  run sudo /usr/local/bin/twm-boot-logo
  ok "boot screen set; you will see it on the next reboot"
}

[ "$DRY" = 1 ] && say "dry run: nothing will change"
[ "$DO_LOCK" = 1 ]   && install_lock
[ "$DO_RELOAD" = 1 ] && install_reload
[ "$DO_BOOT" = 1 ]   && install_boot

say "done"
[ "$DO_RELOAD" = 1 ] && say "run 'ryoku reload' to see the new reload cover"
say "to undo: curl -fsSL https://raw.githubusercontent.com/$REPO/$REF/uninstall.sh | bash"
