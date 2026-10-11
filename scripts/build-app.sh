#!/bin/zsh
# Builds build/Seamtype.app from the SwiftPM product, with its data files in
# Contents/Resources (the kana and text trigrams, Korean and English data, AzooKey's Japanese
# dictionary, the menu icon, third-party notices), then checks the
# bundle can actually load them with `Seamtype --selftest`.
#
#   scripts/build-app.sh                               this Mac's architecture
#   SEAMTYPE_ARCHS="arm64 x86_64" scripts/build-app.sh   universal (release.sh)
set -euo pipefail
setopt extended_glob
cd "${0:A:h}/.."

archs=(${=SEAMTYPE_ARCHS:-})
flags=()
for arch in $archs; do flags+=(--arch $arch); done
swift build -c release --product Seamtype $flags
bin=$(swift build -c release --product Seamtype $flags --show-bin-path)
app=build/Seamtype.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/Seamtype" "$app/Contents/MacOS/Seamtype"
cp Resources/Info.plist "$app/Contents/Info.plist"
# The input source's name in System Settings comes from these, not Info.plist.
cp -R Resources/*.lproj "$app/Contents/Resources/"
data=Sources/SeamtypeCore/Data
cp $data/kana_trigrams.txt $data/text_trigrams.txt $data/korean_syllables.txt $data/korean_words.txt $data/korean_vocabulary.txt $data/english_words.txt "$app/Contents/Resources/"
dictionary=.build/checkouts/AzooKeyKanaKanjiConverter/Sources/KanaKanjiConverterModuleWithDefaultDictionary/azooKey_dictionary_storage/Dictionary
[[ -d "$dictionary" ]] || { echo "missing $dictionary (swift package resolve)"; exit 1; }
cp -R "$dictionary" "$app/Contents/Resources/Dictionary"
swift scripts/make-icon.swift "$app/Contents/Resources/Seamtype.tiff"
# The pause indicator under the caret (PauseHUD) shows the same mark, struck through while paused.
swift scripts/make-icon.swift --slash "$app/Contents/Resources/SeamtypePaused.tiff"

# Licenses of everything compiled or copied into the app (MIT and Apache-2.0 ask for them
# to travel with the binary). A dependency without a license file stops the build.
notices="$app/Contents/Resources/ThirdPartyNotices.txt"
section() { printf '\n\n==== %s ====\n\n' "$1" >> "$notices"; cat "$2" >> "$notices"; }
print -r -- "Seamtype includes the following third-party software and data." > "$notices"
for checkout in .build/checkouts/*(/); do
  license=( $checkout/(#i)(license|copying)*(N.) )
  [[ -n "$license" ]] || { echo "no license file in $checkout"; exit 1; }
  section "${checkout:t} (Swift package)" "$license[1]"
done
section "llama.cpp (linked through AzooKeyKanaKanjiConverter)" scripts/third-party/llama.cpp-LICENSE
section "azooKey dictionary (Contents/Resources/Dictionary)" "${dictionary:h}/LICENSE"
section "Tatoeba (kana, written-Japanese, Korean syllable and word models)" scripts/third-party/tatoeba.txt
section "SCOWL (english_words.txt)" scripts/third-party/scowl-Copyright
section "FrequencyWords (korean_vocabulary.txt)" scripts/third-party/frequencywords.txt
codesign --force --sign - "$app"

"$app/Contents/MacOS/Seamtype" --selftest
# The Intel half too, through Rosetta.
if (( ${archs[(Ie)x86_64]} )) && [[ $(uname -m) == arm64 ]]; then arch -x86_64 "$app/Contents/MacOS/Seamtype" --selftest; fi
# Running it registered this copy with LaunchServices: macOS could then pick it, not the
# installed one, when it launches the input method, and nothing starts.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$app" 2>/dev/null || true
echo "built $app"
