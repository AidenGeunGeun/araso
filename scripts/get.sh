#!/bin/sh
# Installs the latest Araso release into ~/Library/Input Methods and registers it:
#
#   curl -fsSL https://raw.githubusercontent.com/nyttastudio/araso/main/scripts/get.sh | sh
#
# If Araso is already installed it asks what to do; to choose without the question:
#   … | sh -s -- --reinstall              replace it, keep settings and learned words
#   … | sh -s -- --clean                  remove it with settings and learned words, then install
#   … | sh -s -- --uninstall [--delete-data]
# Without a terminal to ask in, it reinstalls, unless the installer package's copy is in /Library:
# then it stops, since that copy can only be removed with a password.
#
# The app in the release zip is signed with the Developer ID and notarized; nothing in it runs until
# that is checked (Araso's team, notarized), since it becomes the input method that sees every
# key. A download made with curl isn't quarantined anyway; the flag is cleared in case it's there.
# ARASO_ZIP=/path/to/Araso.zip installs a local zip instead (for trying a build); one built
# without the Developer ID needs ARASO_UNSIGNED=1 as well.
set -eu

url="https://github.com/nyttastudio/araso/releases/latest/download/Araso.zip"
dest="$HOME/Library/Input Methods"
app="$dest/Araso.app"
system="/Library/Input Methods/Araso.app"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

action="" deletedata=""
for arg in "$@"; do
  case $arg in
    --reinstall) action=reinstall ;;
    --clean) action=clean ;;
    --uninstall) action=uninstall ;;
    --delete-data) deletedata=--delete-data ;;
    *) echo "usage: get.sh [--reinstall | --clean | --uninstall [--delete-data]]" >&2; exit 2 ;;
  esac
done

if [ -z "$action" ] && { [ -d "$app" ] || [ -d "$system" ]; }; then
  action=reinstall
  if (exec </dev/tty) 2>/dev/null; then
    echo "Araso is already installed:"
    [ -d "$app" ] && echo "  $app"
    [ -d "$system" ] && echo "  $system (the installer package)"
    cat <<'MSG'
  1) Reinstall: replace it, keep settings and learned words
  2) Clean reinstall: remove it with its settings and learned words, then install
  3) Uninstall (keep settings and learned words)
  4) Uninstall and delete settings and learned words
  5) Cancel
MSG
    printf 'Choose [1]: '
    read -r answer </dev/tty || answer=""
    case ${answer:-1} in
      1) ;;
      2) action=clean ;;
      3) action=uninstall ;;
      4) action=uninstall deletedata=--delete-data ;;
      *) echo "Nothing changed."; exit 0 ;;
    esac
  fi
fi

# The pkg's copy in /Library has to go before this one goes into ~/Library: two copies are the
# same input method twice, and macOS may launch either. Removing it needs an administrator, asked
# for now; without a terminal, or without the password, nothing is installed.
if [ "$action" = reinstall ] && [ -d "$system" ]; then
  if ! (exec </dev/tty) 2>/dev/null; then
    echo "Araso from the installer package is in /Library/Input Methods; nothing was installed." >&2
    echo "Update it with the package, or run this in a terminal to replace it." >&2
    exit 1
  fi
  echo "Replacing $system (the installer package's copy) needs your password."
  sudo -v </dev/tty || { echo "Nothing was installed." >&2; exit 1; }
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
if [ -n "${ARASO_ZIP:-}" ]; then
  cp "$ARASO_ZIP" "$work/Araso.zip"
else
  echo "Downloading Araso…"
  curl -fsSL -o "$work/Araso.zip" "$url"
fi
ditto -x -k "$work/Araso.zip" "$work"
[ -d "$work/Araso.app" ] || { echo "The download has no Araso.app." >&2; exit 1; }
if [ "${ARASO_UNSIGNED:-}" != 1 ]; then
  codesign --verify --deep --strict "$work/Araso.app" 2>/dev/null &&
    codesign -dv "$work/Araso.app" 2>&1 | grep -qx 'TeamIdentifier=2UZ65T3U82' &&
    spctl --assess --type execute "$work/Araso.app" 2>/dev/null ||
    { echo "The downloaded Araso.app isn't signed by Araso's developer and notarized; nothing was installed." >&2; exit 1; }
fi
xattr -dr com.apple.quarantine "$work/Araso.app" 2>/dev/null || true

# Uninstalling goes through the app (what About → Uninstall… does): both copies, the pkg's
# receipt (macOS asks for the password), the input source and the processes.
if [ "$action" = uninstall ] || [ "$action" = clean ]; then
  [ "$action" = clean ] && deletedata=--delete-data
  "$work/Araso.app/Contents/MacOS/Araso" --uninstall $deletedata
  "$lsregister" -u "$work/Araso.app" 2>/dev/null || true
  [ "$action" = uninstall ] && exit 0
fi

mkdir -p "$dest"
# Swapped by renaming within the folder, so there is never a moment without a Araso.app there
# for macOS to launch (the old one keeps running meanwhile).
rm -rf "$dest/.Araso.app.new" "$dest/.Araso.app.old"
ditto "$work/Araso.app" "$dest/.Araso.app.new"
[ -d "$app" ] && mv "$app" "$dest/.Araso.app.old"
mv "$dest/.Araso.app.new" "$app"
# Stopped only after the new copy is in place: macOS launches an input method from whatever is on
# disk when an app asks, so stopping it earlier only starts the old code again under a new pid.
# SIGTERM, then SIGKILL whatever is left, and wait until it is gone (as vChewing's installer does):
# a Araso still running would keep the old code, and registering may start one.
pkill -x Araso 2>/dev/null || true
i=0; while pgrep -x Araso >/dev/null && [ $i -lt 30 ]; do sleep 0.1; i=$((i+1)); done
pkill -9 -x Araso 2>/dev/null || true
i=0; while pgrep -x Araso >/dev/null && [ $i -lt 30 ]; do sleep 0.1; i=$((i+1)); done
# Before registering: a register that fails ends the script, and the old copy left in the folder
# would be the same input method twice.
rm -rf "$dest/.Araso.app.old"
"$app/Contents/MacOS/Araso" --register
# Two copies make two input methods, and macOS may launch the wrong one: a reinstall the user
# chose takes the pkg's copy out (with its receipt). Only after this copy is registered: removed
# first, it takes the input source (and the user's choice to use it) along.
if [ "$action" = reinstall ] && [ -d "$system" ] && (exec </dev/tty) 2>/dev/null; then
  sudo rm -rf "$system" </dev/tty && sudo pkgutil --forget com.nyttastudio.inputmethod.Araso.pkg >/dev/null 2>&1 || true
fi
# Araso was Legato in 0.2.0 and Seamtype before it, each under its own bundle identifier: to macOS
# other input methods. Their copies go once this one is registered (the settings folder moves on
# Araso's first read).
for old in "$dest/Legato.app" "/Library/Input Methods/Legato.app" "$dest/Seamtype.app" "/Library/Input Methods/Seamtype.app"; do
  [ -d "$old" ] || continue
  "$lsregister" -u "$old" 2>/dev/null || true
  if [ -w "$(dirname "$old")" ]; then
    rm -rf "$old"
  elif (exec </dev/tty) 2>/dev/null && sudo rm -rf "$old" </dev/tty; then
    sudo pkgutil --forget com.nyttastudio.inputmethod.Legato.pkg >/dev/null 2>&1 || true
    sudo pkgutil --forget com.aimdevlee.inputmethod.Seamtype.pkg >/dev/null 2>&1 || true
  else
    echo "Note: $(basename "$old" .app) (Araso's earlier name) is still in $(dirname "$old"); remove it."
  fi
done
pkill -x Legato 2>/dev/null || true
pkill -x Seamtype 2>/dev/null || true
killall TextInputMenuAgent 2>/dev/null || true
# The switch indicator by the caret keeps the icon it read first (they ignore SIGTERM).
killall -KILL CursorUIViewService TextInputSwitcher 2>/dev/null || true

[ -d "$system" ] &&
  echo "Note: another copy is in /Library/Input Methods; remove one of them."
cat <<'MSG'

Araso is installed. Add it in System Settings → Keyboard → Input Sources → Edit… → + →
Korean → Araso (log out and back in once if it isn't listed), then pick it from the input menu.
MSG
