<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/logo-dark.svg">
    <img src="docs/media/logo-light.svg" width="150" alt="Seamtype: A, 아, あ">
  </picture>
</p>

<h1 align="center">Seamtype</h1>

<p align="center"><b>흐름대로 써진다 · 流れるままに · Type as it flows</b></p>

<p align="center"><a href="README.md">한국어</a> · English</p>

Type everything on the English (QWERTY) layout and stop pressing the language-switch key.
Seamtype is a macOS input method that decides **per word** whether you meant English,
Korean (2-set / 두벌식) or — if you turn it on — Japanese (romaji), and commits the right one.

```
dkssudgktpdy, hello world!          →  안녕하세요, hello world!
dlrjs githubdp commitgkf rjdi       →  이건 github에 commit할 거야
kyouhagoogledekensaku ␣ ⏎           →  今日はgoogleで検索
```

<p align="center">
  <img src="docs/media/demo.gif" width="720" alt="Typing on QWERTY into TextEdit: 안녕하세요, hello world! / 이건 github에 commit할 거야. / 今日はgoogleで検索">
</p>

## Why

I live in Japan and mix Korean, English and Japanese every day. With three input sources, I was
forever pressing the switch key, or typing a word in the wrong language. Then
[Meltype](https://github.com/yksr-melt/Meltype), which mixes Japanese and English without switching,
inspired me to build one input method for all three.

## Keys

While a word is being typed it is underlined and shows the language Seamtype expects.

| Key | English / Korean word | Japanese phrase |
| --- | --- | --- |
| letters | extend the word | extend the phrase (kana preview) |
| **Esc** | switch reading: English → English+particle → Korean → Japanese | same |
| **⇧Esc** | switch reading, in every app (where Esc is set to go to the app) | same |
| Delete | remove the last keystroke | same |
| **Space** | commit, then a space | **convert to kanji** (candidate window) |
| `, . ? !` | commit, then the key | stay in the phrase as 、。？！ |
| `-` | commit, then `-` | ー |
| Return | commit, and the app gets Return | commit the kana only (no newline) |
| ⌃K / F7, ⌃J / F6 | (the app's shortcut) | katakana / hiragana (Space flips, Return commits) |
| Tab, arrows, ⌘/⌃/⌥ | commit, the app gets the key | same |

While converting (candidate window open):

| Key | Effect |
| --- | --- |
| Space / ↓, ↑ | next / previous candidate |
| ←, → | shorten / lengthen the first clause (`今日は｜いいてんき`) |
| 1–9 | commit that candidate |
| Return | commit the selected candidate |
| Esc / Delete | back to the kana |
| letters, punctuation | commit, then keep typing |

A candidate that covers only the start of the reading (`今日は` for きょうはいいてんきですね)
commits that part and keeps converting the rest — clause-by-clause conversion.

**Undo a wrong guess after the fact:** right after a word was committed with space or
punctuation, **Esc** (⇧Esc where Esc goes to the app) switches that word to its next reading;
pressing it again keeps cycling. This needs the caret still right after the word and an app
that lets Seamtype read the text there; otherwise the key goes to the app. Any other key ends
the window.

**Learning:** a correction changes only that word, so a stray Esc doesn't stick. Correct the
same keys the same way a second time and Seamtype remembers it for good; switching a word
back to Seamtype's own guess forgets it.

**Esc that belongs to the app** (closing popups in an editor): set that app's Esc key (or the
default's) to "Send to app" in the per-app settings — the word goes in as shown and the app gets
Esc. Use ⇧Esc to switch there.

**vim:** in an app where you use vim (a terminal), set the Esc key to "Vim". It works like "Send to
app", and in normal mode after Esc (or ⌃[) keys go straight to vim instead of being held as a
word, so `dd`, `ciw` and `:wq⏎` run key by key. Entering insert mode with `i a o I A O s S C R gi` or
`c` plus its motion (`ciw`, `cw`) starts deciding words again. Letters inside commands (`diw`, `fa`,
`ri`), visual mode and the `:`/`/` command line don't count as insert mode. Quitting vim (`:wq⏎`,
`ZZ`) starts deciding words again too, so you can type at the shell right away. Mappings that enter
insert mode can't be seen; press ⇧Esc to start deciding words again.

## Settings

The input menu (menu bar, while Seamtype is selected) switches Japanese and live conversion,
sets how strict Seamtype is in the app in front and whether Esc goes to the app (or to vim), or
turns it off there, undoes the last
learned word, and opens the settings window: general switches, per-app behavior, and the
learned words (forget one or all); the kanji candidate order resets under Japanese. Changes apply at once.

Both write `~/Library/Application Support/Seamtype/settings.json` (missing keys keep the
default), which can also be edited by hand:

```json
{ "japanese": true, "liveConversion": true }
```

- `japanese` (default **off**): detect romaji Japanese and convert it.
- `liveConversion` (default off): like macOS Live Conversion, a Japanese phrase shows its top
  kanji candidate while you type (`今日はいい天気でs`) and Return commits it as shown. Space
  opens the candidate window at the next candidate; Esc shows the kana (Esc again switches
  language). Short readings only change into kanji (`と` stays `と`, `私` converts). The top
  candidate is right for about 4 in 5 short phrases and 2 in 3 whole sentences (below), so
  glance before Return. Conversion takes 8–21 ms a keystroke.

Per-app behavior lives in `apps.json` next to it. `"*"` is your default for every app; an
app (by bundle identifier, a key ending in `.` matches as a prefix) changes only the keys it
names and follows the default for the rest. No app is listed unless you list it:

```json
{ "*":                     { "escapeToApp": true },
  "com.apple.Terminal":    { "conversionThreshold": 0.97, "vim": true },
  "com.example.Game":      { "enabled": false } }
```

- `enabled` (default true): false passes every key through (plain English).
- `conversionThreshold` (default `0.5`): convert away from the typed letters only when at
  least this sure. `0.97` ("엄격하게", strict) keeps short shell commands from turning into
  Hangul in a terminal; `0.5` converts more Korean when you write prose.
- `escapeToApp` (default false): Esc goes to the app and ⇧Esc switches (for editors).
- `vim` (default false): on top of `escapeToApp`, vim's normal-mode commands after Esc go straight
  through (see **vim** above).

After editing these files by hand, restart the input method: `pkill -x Seamtype`.

## How it decides

Locally, in this order — a keystroke's preview takes at most ~3 ms, a word's final decision
~7 ms, even 70 letters into a phrase:

1. **Your corrections** (made twice, see Learning) always win (`lexicon.json`).
2. **Mixed words:** `githubdp` → `github에`, `UIrkxdmsrjs` → `UI같은건` when the front
   looks English (or is typed in capitals) and the end is a Korean particle or ending;
   `hellodnjfem` → `hello월드` for an English word and a Korean word that are both in the word
   lists. With Japanese on: `githubde` → `githubで` for a known English word plus one case
   particle, and Korean and Japanese typed together, `dlfurrireki` → `이력履歴`, `rirekifmf` →
   `履歴를`, `kyouhaehtlfkrdms` → `今日は도시락은`, only when the keys break both as Hangul and as
   romaji, so ordinary Japanese phrases stay whole.
3. **Rules:** shift on a letter with no shifted jamo (`Hello`, `API`) is English.
4. **Heuristic:** the keys are scored per keystroke as English (character trigrams, and a
   floor for words in the SCOWL list, by how common they are), Korean (2-set syllable
   frequencies, and a floor for words seen in Korean text) and Japanese (romaji → kana
   trigrams, with English words inside the phrase split out), plus a nudge toward the
   previous word's language — weaker when the keys are a word of another language and not
   of the previous one, which is someone switching language. A known English word needs a
   clear Japanese win before it turns into kana.

Kanji come from [AzooKey](https://github.com/azooKey/AzooKeyKanaKanjiConverter)'s dictionary
converter, reranked by a character trigram model of written Japanese; AzooKey also learns
from what you pick.

### Held-out results

2,011 English words, 1,987 Korean words and 2,000 Japanese phrases from held-out sentences,
never used to build the models (`tools/prepare.sh`):

| | Japanese off (en/ko) | Japanese on (en/ko/ja) |
| --- | --- | --- |
| Accuracy | 99.80% | 99.48% |

That set counts every word once and seldom puts it after the other language. Real text is
mostly its most frequent words, and switching language mid-sentence is the point, so the
10,000 most frequent English and Korean words are also scored after each kind of word
(`tools/eval_context.py`, Japanese on) — wrong among the top 1,000 / top 10,000:

| | after nothing | after the same language | after the other | after Japanese |
| --- | --- | --- | --- | --- |
| Korean words | 9 / 42 | 2 / 16 | 16 / 159 | 9 / 46 |
| English words | 2 / 47 | 0 / 21 | 8 / 71 | 2 / 86 |

(Before the SCOWL and Korean word lists and the switch-aware nudge: 94 / 785 in all, now
48 / 488.) These lists were used while tuning those rules, so they're a guide, not a held-out
score. Many remaining misses are genuinely ambiguous keys: `so`/내, `go`/해, `did`/양.

Kanji conversion, top candidate exactly matching the original text (held-out Tatoeba):

| | AzooKey alone | + reranking | correct one in the list |
| --- | --- | --- | --- |
| 2–3 word phrases | 69.5% | **81.0%** | 96.2% |
| whole sentences | 56.0% | **66.0%** | 82.2% |

Exact match counts kana/kanji style differences (ひとまとめ vs 一まとめ) as misses.

## Install

One line in Terminal installs the latest release into `~/Library/Input Methods` (Apple silicon
and Intel, no administrator rights):

```sh
curl -fsSL https://raw.githubusercontent.com/aimdevlee/seamtype/main/scripts/get.sh | sh
```

Releases aren't signed or notarized with an Apple Developer ID. A download made with `curl` isn't
stopped by Gatekeeper, but if you download `Seamtype.zip` from
[Releases](https://github.com/aimdevlee/seamtype/releases) in a browser and install it yourself,
unzip it into `~/Library/Input Methods` and clear its quarantine flag, or the input method won't run:

```sh
xattr -dr com.apple.quarantine ~/Library/Input\ Methods/Seamtype.app
```

Or build from source (Xcode or the Command Line Tools, Swift 6.1 or later):

```sh
scripts/install.sh        # builds and self-tests Seamtype.app, installs it
```

Then **System Settings → Keyboard → Input Sources → Edit… → + → Korean → Seamtype**.
If Seamtype isn't listed, log out and back in once. All of these install to the same place; a
pkg you build with `scripts/release.sh` installs into `/Library/Input Methods` instead, so use only
one or you'd get two copies of the input method.

**Uninstall:** remove Seamtype from the input sources, then in Terminal:

```sh
pkill -x Seamtype
rm -rf ~/Library/Input\ Methods/Seamtype.app
rm -rf ~/Library/Application\ Support/Seamtype   # only to drop settings and learned words
```

If you installed the pkg, the app is in `/Library/Input Methods/Seamtype.app` (remove it with
`sudo rm -rf`).

Resources: ~50 MB of memory (plus the ~35 MB Japanese dictionary when Japanese is on), a
~47 MB app, nothing else running. Keystrokes never leave the input method.

## Develop

```sh
swift test                     # 102 tests: composers, engines, sessions, settings, end to end
scripts/typing-test/run.sh     # real key events into TextEdit through the installed Seamtype
scripts/record-demo/record.sh  # records the README demo (docs/media/demo.gif) from real typing
swift scripts/make-readme-logo.swift docs/media  # the README logo (animated SVG)
scripts/release.sh             # universal (arm64 + x86_64) zip and pkg for a release; signed and notarized with a Developer ID
tools/prepare.sh               # accuracy (downloads word lists, Tatoeba and SCOWL once)
tools/prepare.sh --models      # rebuild the data in Sources/SeamtypeCore/Data first
SEAMTYPE_TIMING=1 swift run -c release seamtype-cli --decide --japanese < keys.tsv  # + time per decision
swift run seamtype-cli -v "dkssud gksrmf hello"               # English/Korean, with scores
printf 'kyouhagoogledekensaku\t\n' | swift run seamtype-cli --decide --japanese
printf 'きょうはいいてんきですね\n' | swift run seamtype-cli --convert
```

| Path | What |
| --- | --- |
| `Sources/SeamtypeCore` | composers, engines, conversion, `InputSession` (all typing logic) |
| `Sources/Seamtype` | InputMethodKit server, a thin controller over `InputSession`, candidate window |
| `Sources/SeamtypeCore/Data` | kana and written-Japanese trigrams, Korean syllables and words, English words |
| `tools/` | corpus → romaji, model builders, evaluation set and accuracy (python3, no packages) |

## Known limits

- Never tested end to end in every app: secure fields (passwords) bypass input methods, and
  undo-after-commit needs apps that report their caret and text.
- Where Esc doesn't go to the app, Esc right after a word (e.g. to close a popup) changes that
  word first (not learned unless repeated); list such apps with `"escapeToApp": true`.
- Japanese: only the first clause is resized with ←/→ (Return commits it and moves on to the
  rest); rare words still need the candidate list.

## License and data

Seamtype is MIT licensed ([LICENSE](LICENSE)).

The app carries the licenses of everything compiled or copied into it in
`Contents/Resources/ThirdPartyNotices.txt`, collected by `scripts/build-app.sh`.

- AzooKey Kana-Kanji Converter: MIT; its dictionary: Apache-2.0.
- Tatoeba sentences (kana and written-Japanese models, Korean syllable and word counts;
  evaluation): CC-BY 2.0 FR, https://tatoeba.org.
- English words and how common they are: [SCOWL](http://wordlist.aspell.net) (permissive,
  notice in the app). macOS's `/usr/share/dict/words` trains the letter trigrams at runtime.
- English/Korean frequency lists:
  [hermitdave/FrequencyWords](https://github.com/hermitdave/FrequencyWords), CC-BY-SA 4.0. Used
  for evaluation; the Korean list also ships as `korean_vocabulary.txt` (for splitting an English
  word from a Korean one), under the same license, with its notice in the app.
