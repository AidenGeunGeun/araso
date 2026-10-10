#!/bin/zsh
# Types test cases into a new TextEdit document with real key events, through the installed
# Seamtype (selected for the run; the previous input source comes back after), and compares
# the text. Needs Seamtype enabled in Input Sources and Accessibility permission for the
# terminal. TextEdit takes the focus for about a minute.
#
# Each suite runs with its own settings.json: cases.tsv with Japanese on, live.tsv with live
# conversion too. The user's settings and learning files (the cases' Esc corrections would
# be learned like any other; so would its kanji choices) are backed up first and restored
# afterwards, and Seamtype restarts so it reads them again.
#
#   scripts/typing-test/run.sh
set -euo pipefail
here="${0:A:h}"
support="$HOME/Library/Application Support/Seamtype"
app="$HOME/Library/Input Methods/Seamtype.app"
files=(settings.json lexicon.json)
dirs=(azooKey)  # AzooKey's kanji learning
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Stop before touching any settings if there is no Seamtype input source to type through.
swift "$here/../enable-input-source.swift" --check com.aimdevlee.inputmethod.Seamtype || {
  echo "Seamtype isn't an enabled input source: add it in System Settings → Keyboard → Input Sources"
  exit 1
}

swiftc -O -o "$work/typer" "$here/typer.swift"
mkdir -p "$support"
for f in $files; do
  [[ -f "$support/$f" ]] && cp "$support/$f" "$work/$f"
done
for d in $dirs; do
  [[ -d "$support/$d" ]] && cp -R "$support/$d" "$work/$d"
done
restore() {
  pkill -x Seamtype || true  # first, so it can't save its learning over the restored copy
  sleep 1
  for f in $files; do
    if [[ -f "$work/$f" ]]; then cp "$work/$f" "$support/$f"; else rm -f "$support/$f"; fi
  done
  for d in $dirs; do
    rm -rf "$support/$d"
    if [[ -d "$work/$d" ]]; then cp -R "$work/$d" "$support/$d"; fi
  done
}
trap 'restore; rm -rf "$work"' EXIT

suite() {
  echo "== $1"
  print -r -- "$2" > "$support/settings.json"
  pkill -x Seamtype || true
  sleep 1
  # macOS starts it again, with these settings, when the next app needs it. Starting it
  # ourselves (open) gives a process apps don't connect to.
  # A failing suite must not end the script here: zsh skips the EXIT trap (the restore) when
  # errexit fires inside a function.
  "$work/typer" "$here/$1" || failed=1
}
failed=0
suite cases.tsv '{ "japanese": true }'
suite live.tsv '{ "japanese": true, "liveConversion": true }'
exit $failed
