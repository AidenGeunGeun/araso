#!/bin/zsh
# Records the README demo's footage: types the examples into page.html in Safari through the installed
# Araso (demo.swift) while screencapture records the screen, into build/demo/ (demo.mov and
# keys.json). The film in film/ is made from that footage (render.sh).
# Needs Araso installed and enabled, and Accessibility and Screen Recording permission for
# the terminal. Takes over the keyboard, pointer and focus for about half a minute.
#
# The user's settings and learning files are backed up and restored, as in typing-test/run.sh,
# so the demo runs with Japanese on and nothing else (default keys, no remembered words or kanji
# choices) and doesn't learn from its own typing.
#
#   scripts/record-demo/record.sh
set -euo pipefail
here="${0:A:h}"
root="${here:h:h}"
support="$HOME/Library/Application Support/Araso"
files=(settings.json apps.json dictionary.json lexicon.json apple-learning.json)
dirs=(azooKey)
work=$(mktemp -d)

swift "$here/../enable-input-source.swift" --check com.nyttastudio.inputmethod.Araso || {
  echo "Araso isn't an enabled input source: add it in System Settings → Keyboard → Input Sources"
  exit 1
}

swiftc -O -o "$work/demo" "$here/demo.swift"
mkdir -p "$support"
for f in $files; do [[ -f "$support/$f" ]] && cp "$support/$f" "$work/$f"; done
for d in $dirs; do [[ -d "$support/$d" ]] && cp -R "$support/$d" "$work/$d"; done
# The page over localhost: Safari asks to confirm a file: URL opened by a script.
port=8765
python3 -m http.server $port --bind 127.0.0.1 --directory "$here" >/dev/null 2>&1 &
server=$!
restore() {
  kill $server 2>/dev/null || true
  pkill -x Araso || true
  sleep 1
  for f in $files; do
    if [[ -f "$work/$f" ]]; then cp "$work/$f" "$support/$f"; else rm -f "$support/$f"; fi
  done
  for d in $dirs; do
    rm -rf "$support/$d"
    if [[ -d "$work/$d" ]]; then cp -R "$work/$d" "$support/$d"; fi
  done
  rm -rf "$work"
}
trap restore EXIT

print -r -- '{ "japanese": true }' > "$support/settings.json"
rm -f "$support/apps.json" "$support/dictionary.json" "$support/lexicon.json" "$support/apple-learning.json"
rm -rf "$support/azooKey"
pkill -x Araso || true
sleep 1

out="$root/build/demo"
rm -rf "$out"; mkdir -p "$out"
"$work/demo" "$out" "http://127.0.0.1:$port/page.html"
ls -lh "$out"
