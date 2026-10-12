#!/bin/zsh
# Builds, self-tests and installs the input method.
#   scripts/install.sh [--reinstall | --clean | --uninstall [--delete-data]]
# If Seamtype is already installed it asks what to do (as get.sh does); without a terminal to ask
# in, or with --reinstall, it replaces the copy in ~/Library/Input Methods.
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
system="/Library/Input Methods/Seamtype.app"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
tty=false
(exec </dev/tty) 2>/dev/null && tty=true

if [[ -z $action ]] && [[ -d "$dest/Seamtype.app" || -d $system ]]; then
  action=reinstall
  if $tty; then
    echo "Seamtype is already installed:"
    [[ -d "$dest/Seamtype.app" ]] && echo "  $dest/Seamtype.app"
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

scripts/build-app.sh

# Uninstalling goes through the new build (what About → Uninstall… does): both copies, the pkg's
# receipt (macOS asks for the password), the input source and the processes.
if [[ $action == (uninstall|clean) ]]; then
  [[ $action == clean ]] && deletedata=(--delete-data)
  build/Seamtype.app/Contents/MacOS/Seamtype --uninstall $deletedata
  # Running it registered the build with LaunchServices again (build-app.sh had taken it off).
  $lsregister -u build/Seamtype.app 2>/dev/null || true
  [[ $action == uninstall ]] && exit 0
fi

# Two copies make two input methods, and macOS may launch the wrong one: a reinstall the user
# chose in the terminal takes the pkg's copy out (with its receipt).
if [[ $action == reinstall && -d $system ]] && $tty; then
  echo "Removing $system (the installer package's copy) needs your password."
  sudo rm -rf $system </dev/tty && sudo pkgutil --forget com.aimdevlee.inputmethod.Seamtype.pkg >/dev/null 2>&1 || true
fi

mkdir -p "$dest"
rm -rf "$dest/Seamtype.app"
cp -R build/Seamtype.app "$dest/"
# Stopped after the new copy is in place: a keystroke during the install launches the old one
# again, and it would run (old code over new files) until a restart.
pkill -x Seamtype 2>/dev/null || true
echo "installed $dest/Seamtype.app"
[[ -d $system ]] &&
  echo "warning: a release copy is also in /Library/Input Methods; remove one of them"

id=com.aimdevlee.inputmethod.Seamtype
enabled=false
# Registering also forgets other copies LaunchServices knows.
"$dest/Seamtype.app/Contents/MacOS/Seamtype" --register
if swift scripts/enable-input-source.swift --check $id; then enabled=true; else
  for _ in {1..10}; do  # an input source the user already added comes back within ~30 s
    sleep 3
    swift scripts/enable-input-source.swift --check $id && { enabled=true; break; }
  done
fi
# The input menu keeps the list from before the reinstall (without Seamtype) until it restarts,
# and the switch indicator by the caret its icon (they ignore SIGTERM; launchd brings them back).
$enabled && killall TextInputMenuAgent 2>/dev/null || true
$enabled && killall -KILL CursorUIViewService TextInputSwitcher 2>/dev/null || true
$enabled && echo "input source $id is enabled" ||
  echo "input source $id isn't enabled: add it in System Settings → Keyboard → Input Sources"

cat <<'EOF'

Next: pick "Seamtype" from the input menu. If it isn't there, add it in
System Settings → Keyboard → Input Sources → Edit… → + → Korean, or log out and back in once.
EOF
