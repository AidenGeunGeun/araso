#!/bin/zsh
# Builds, self-tests and installs the input method.
#   scripts/install.sh [--reinstall | --clean | --uninstall [--delete-data]]
# If Legato is already installed it asks what to do (as get.sh does); without a terminal to ask
# in, or with --reinstall, it replaces the copy in ~/Library/Input Methods; it stops instead when the
# installer package's copy is in /Library and there is no terminal to ask for the password.
set -euo pipefail
cd "${0:A:h}/.."

action="" deletedata=()
for arg in "$@"; do
  case $arg in
    --reinstall) action=reinstall ;;
    --clean) action=clean ;;
    --uninstall) action=uninstall ;;
    --delete-data) deletedata=(--delete-data) ;;
    *) echo "usage: scripts/install.sh [--reinstall | --clean | --uninstall [--delete-data]]" >&2; exit 2 ;;
  esac
done

dest="$HOME/Library/Input Methods"
system="/Library/Input Methods/Legato.app"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
tty=false
(exec </dev/tty) 2>/dev/null && tty=true

if [[ -z $action ]] && [[ -d "$dest/Legato.app" || -d $system ]]; then
  action=reinstall
  if $tty; then
    echo "Legato is already installed:"
    [[ -d "$dest/Legato.app" ]] && echo "  $dest/Legato.app"
    [[ -d $system ]] && echo "  $system (the installer package)"
    cat <<'EOF'
  1) Reinstall: replace it, keep settings and learned words
  2) Clean reinstall: remove it with its settings and learned words, then install
  3) Uninstall (keep settings and learned words)
  4) Uninstall and delete settings and learned words
  5) Cancel
EOF
    read -r "answer?Choose [1]: " </dev/tty || answer=""
    case ${answer:-1} in
      1) ;;
      2) action=clean ;;
      3) action=uninstall ;;
      4) action=uninstall deletedata=(--delete-data) ;;
      *) echo "Nothing changed."; exit 0 ;;
    esac
  fi
fi

# The pkg's copy in /Library has to go before this one goes into ~/Library: two copies are the
# same input method twice, and macOS may launch either. Removing it needs an administrator, asked
# for now (sudo keeps it for the rest of the install); without a terminal, or without the password,
# nothing is installed.
if [[ $action == reinstall && -d $system ]]; then
  if ! $tty; then
    echo "Legato from the installer package is in /Library/Input Methods; nothing was installed." >&2
    echo "Run scripts/install.sh in a terminal to replace it, or update with the package." >&2
    exit 1
  fi
  echo "Replacing $system (the installer package's copy) needs your password."
  sudo -v </dev/tty || { echo "Nothing was installed." >&2; exit 1; }
fi

scripts/build-app.sh

# Uninstalling goes through the new build (what About → Uninstall… does): both copies, the pkg's
# receipt (macOS asks for the password), the input source and the processes.
if [[ $action == (uninstall|clean) ]]; then
  [[ $action == clean ]] && deletedata=(--delete-data)
  build/Legato.app/Contents/MacOS/Legato --uninstall $deletedata
  # Running it registered the build with LaunchServices again (build-app.sh had taken it off).
  $lsregister -u build/Legato.app 2>/dev/null || true
  [[ $action == uninstall ]] && exit 0
fi

mkdir -p "$dest"
# Swapped by renaming within the folder, so there is never a moment without a Legato.app there
# for macOS to launch (the old one keeps running meanwhile).
rm -rf "$dest/.Legato.app.new" "$dest/.Legato.app.old"
replaced=false
[[ -d "$dest/Legato.app" ]] && replaced=true
ditto build/Legato.app "$dest/.Legato.app.new"
[[ -d "$dest/Legato.app" ]] && mv "$dest/Legato.app" "$dest/.Legato.app.old"
mv "$dest/.Legato.app.new" "$dest/Legato.app"
# Stopped only after the new copy is in place: macOS launches an input method from whatever is on
# disk when an app asks, so stopping it earlier only starts the old code again under a new pid.
# SIGTERM, then SIGKILL whatever is left, and wait until it is gone (as vChewing's installer does):
# a Legato still running would keep the old code, and registering may start one.
pkill -x Legato 2>/dev/null || true
i=0; while pgrep -x Legato >/dev/null && [ $i -lt 30 ]; do sleep 0.1; i=$((i+1)); done
pkill -9 -x Legato 2>/dev/null || true
i=0; while pgrep -x Legato >/dev/null && [ $i -lt 30 ]; do sleep 0.1; i=$((i+1)); done
# Before registering: a register that fails ends the script, and the old copy left in the folder
# would be the same input method twice.
rm -rf "$dest/.Legato.app.old"
echo "installed $dest/Legato.app"

id=com.nyttastudio.inputmethod.Legato
enabled=false
# Registering also forgets other copies LaunchServices knows.
"$dest/Legato.app/Contents/MacOS/Legato" --register
# Two copies make two input methods, and macOS may launch the wrong one: a reinstall the user
# chose in the terminal takes the pkg's copy out (with its receipt). Only after this copy is
# registered: removed first, it takes the input source (and the user's choice to use it) along.
if [[ $action == reinstall && -d $system ]] && $tty; then
  sudo rm -rf $system </dev/tty && sudo pkgutil --forget com.nyttastudio.inputmethod.Legato.pkg >/dev/null 2>&1 || true
fi
[[ -d $system ]] &&
  echo "warning: a release copy is also in /Library/Input Methods; remove one of them"
# Legato was Seamtype until 0.2.0, under another bundle identifier: to macOS another input method.
# Its copies go once this one is registered (its settings folder moves on Legato's first read).
for old in "$dest/Seamtype.app" "/Library/Input Methods/Seamtype.app"; do
  [[ -d $old ]] || continue
  $lsregister -u "$old" 2>/dev/null || true
  if [[ -w ${old:h} ]]; then
    rm -rf "$old"
  elif $tty && sudo rm -rf "$old" </dev/tty; then
    sudo pkgutil --forget com.aimdevlee.inputmethod.Seamtype.pkg >/dev/null 2>&1 || true
  else
    echo "warning: Seamtype (Legato's name before 0.2.0) is still in ${old:h}; remove it"
  fi
done
pkill -x Seamtype 2>/dev/null || true
if swift scripts/enable-input-source.swift --check $id; then enabled=true; else
  for _ in {1..10}; do  # an input source the user already added comes back within ~30 s
    sleep 3
    swift scripts/enable-input-source.swift --check $id && { enabled=true; break; }
  done
fi
# The input menu keeps the list from before the reinstall (without Legato) until it restarts,
# and the switch indicator by the caret its icon (they ignore SIGTERM; launchd brings them back).
$enabled && killall TextInputMenuAgent 2>/dev/null || true
$enabled && killall -KILL CursorUIViewService TextInputSwitcher 2>/dev/null || true
$enabled && echo "input source $id is enabled" ||
  echo "input source $id isn't enabled: add it in System Settings → Keyboard → Input Sources"

# An ad hoc copy that replaced one macOS had running isn't started again (build-app.sh says why)
# until the source is re-added; the settings pane is opened for it.
if $replaced && codesign -dv "$dest/Legato.app" 2>&1 | grep -q '^Signature=adhoc'; then
  cat <<'EOF'

This build is signed ad hoc (no Apple Development or Developer ID identity in the keychain), so
macOS won't start the new copy: in System Settings → Keyboard → Input Sources → Edit…, remove
Legato (−) and add it again (+), or log out and back in. An Apple ID signed in to Xcode gives
an Apple Development identity, and then a reinstall needs none of this.
EOF
  open "x-apple.systempreferences:com.apple.Keyboard-Settings.extension" 2>/dev/null || true
fi

cat <<'EOF'

Next: pick "Legato" from the input menu. If it isn't there, add it in
System Settings → Keyboard → Input Sources → Edit… → + → Korean, or log out and back in once.
EOF
