#!/bin/zsh
# Records the README demo: types the examples into TextEdit through the installed Seamtype
# (demo.swift) while screencapture records the window, then makes docs/media/demo.gif.
# Needs Seamtype installed and enabled, and Accessibility and Screen Recording permission for
# the terminal. Takes over the keyboard and focus for about half a minute.
#
# The user's settings and learning files are backed up and restored, as in typing-test/run.sh,
# so the demo runs with Japanese on and doesn't learn from its own typing.
#
#   scripts/record-demo/record.sh
set -euo pipefail
here="${0:A:h}"
root="${here:h:h}"
support="$HOME/Library/Application Support/Seamtype"
files=(settings.json lexicon.json)
dirs=(azooKey)
work=$(mktemp -d)

swift "$here/../enable-input-source.swift" --check com.aimdevlee.inputmethod.Seamtype || {
  echo "Seamtype isn't an enabled input source: add it in System Settings → Keyboard → Input Sources"
  exit 1
}

swiftc -O -o "$work/demo" "$here/demo.swift"
mkdir -p "$support"
for f in $files; do [[ -f "$support/$f" ]] && cp "$support/$f" "$work/$f"; done
for d in $dirs; do [[ -d "$support/$d" ]] && cp -R "$support/$d" "$work/$d"; done
# No spelling underline under github (TextEdit's own setting, put back afterwards).
spelling=$(defaults read com.apple.TextEdit CheckSpellingWhileTyping 2>/dev/null || echo none)
defaults write com.apple.TextEdit CheckSpellingWhileTyping -bool false
restore() {
  if [[ $spelling == none ]]; then
    defaults delete com.apple.TextEdit CheckSpellingWhileTyping 2>/dev/null || true
  else
    defaults write com.apple.TextEdit CheckSpellingWhileTyping -bool $spelling
  fi
  pkill -x Seamtype || true
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
rm -f "$support/lexicon.json"
pkill -x Seamtype || true
sleep 1

"$work/demo" "$work/demo.mov"

# Only the text: the window's top 100 pt (title bar, format bar, ruler) cut off, and a margin in
# the text's background colour (taken from the recording, so light and dark mode both work).
# Then a two-pass palette, 15 fps, 1440 px wide (shown at 720, for retina screens).
# The window is 700 × 400 pt (demo.swift); the crop leaves out its edges and scroll bar too.
bg=$(ffmpeg -hide_banner -loglevel error -i "$work/demo.mov" -vf "crop=8:8:iw*3/4:ih*3/5,scale=1:1" \
  -frames:v 1 -f rawvideo -pix_fmt rgb24 - | xxd -p)
filters="crop=iw*680/700:ih*278/400:iw*2/700:ih*102/400,fps=15,scale=1352:-1:flags=lanczos,pad=1440:ih+88:44:44:color=0x$bg"
ffmpeg -hide_banner -loglevel error -y -i "$work/demo.mov" -vf "$filters,palettegen=stats_mode=diff" "$work/palette.png"
ffmpeg -hide_banner -loglevel error -y -i "$work/demo.mov" -i "$work/palette.png" \
  -lavfi "$filters [x]; [x][1:v] paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" "$root/docs/media/demo.gif"
ls -lh "$root/docs/media/demo.gif"
