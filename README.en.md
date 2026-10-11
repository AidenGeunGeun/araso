<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/logo-dark.svg">
    <img src="docs/media/logo-light.svg" width="150" alt="Seamtype: A, 아, あ">
  </picture>
</p>

<h1 align="center">Seamtype</h1>

<p align="center"><b>흐름대로 써진다 · 流れるままに · Type as it flows</b></p>

<p align="center"><a href="https://nyttastudio.com/seamtype/">Website (Korean)</a> · <a href="README.md">한국어</a> · English</p>

Type everything on the English (QWERTY) layout and stop pressing the language-switch key.
Seamtype is a macOS input method that decides **per word** whether you meant English,
Korean (2-set / 두벌식) or — if you turn it on — Japanese (romaji), and commits the right one.

```
Stay hungry, stay foolishsms wkqtmdml akfdlek.   →  Stay hungry, stay foolish는 잡스의 말이다.
wagahaihanekodearu␣sms thtpzldml thtjfdlek.      →  吾輩は猫である는 소세키의 소설이다.
Hello, worldhasaishonopuroguramudesu␣.           →  Hello, worldは最初のプログラムです。
```

<p align="center">
  <img src="docs/media/demo.gif" width="720" alt="Choosing Seamtype once from the input menu, then typing on QWERTY into Safari without switching the input source again: Stay hungry, stay foolish는 잡스의 말이다. / 吾輩は猫である는 소세키의 소설이다. / Hello, worldは最初のプログラムです。">
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
| Return | commit only (press again for a newline or to send; a setting) | commit as shown, kana or live-converted kanji (no newline) |
| ⌃K / F7, ⌃J / F6 | (the app's shortcut) | katakana / hiragana (Space flips, Return commits) |
| Tab, arrows, ⌘/⌃/⌥ | commit, the app gets the key | same |
| **Right ⌘** (tapped on its own) | pause / resume Seamtype in this text field | same |

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

**Pause:** where every key is a command, like a terminal program that moves with `hjkl` (lazygit,
htop), tap **right ⌘** on its own. The word in progress goes in, and in that text field keys go
through as typed. Tap again, move to another app or text field, or change a setting, to resume. Each tap shows
Seamtype's icon under the caret for a moment, in a blue capsule like the input source indicator,
struck through when paused; the menu bar icon doesn't change, so
later the input menu has it checked. Turn the key off under General in the settings.

**vim:** for neovim put [`scripts/vim/seamtype.lua`](scripts/vim/seamtype.lua) in
`~/.config/nvim/plugin/`; for Vim (8.2 or later, `+job`) put
[`scripts/vim/seamtype.vim`](scripts/vim/seamtype.vim) in `~/.vim/plugin/`. Vim then tells Seamtype on
every mode change, and outside insert mode (normal, visual, command line) keys go straight to vim
instead of being held as a word, so `s`, `dd`, `ciw` and `:wq⏎` run key by key; words are decided
only in insert mode. Inside vim, Esc always goes to vim, so no per-app setting is needed. Once vim
quits, words are decided again at the shell.
- The signal is `Seamtype --vim insert|normal|off --app <bundle id>`, sent on mode changes
  (entering and leaving insert mode, start, quit, focus), not on keys. The bundle identifier is
  `$__CFBundleIdentifier`, which macOS sets for every app, so nothing needs setting up per terminal
  (Ghostty, Terminal, iTerm2, VS Code…), and the signal reaches only that app's text field. A
  signal without `--app` is taken only where Esc goes to the app.
- Attached to tmux from a different terminal than the one that started its server, the bundle
  identifiers differ and the signal is ignored.
- If Vim doesn't see the terminal's focus changes, moving from its pane to a shell pane goes
  unnoticed; press ⇧Esc there to start deciding words again.

## Settings

The input menu (menu bar, while Seamtype is selected) pauses Seamtype in the text field (like
right ⌘); for the app in front, turns word conversion on or off and, under it, sets the conversion
threshold (Normal/Strict) and whether Esc goes to the app (both greyed while conversion is off), or
drops the app's settings; switches Japanese and live conversion; undoes the last learned word; and
opens Try Typing, the remembered words and the settings window. The settings window has general
switches, Try Typing (how each word was decided, with scores), per-app behavior, the learned words
(forget one or all) and About; the kanji candidate order resets under Japanese. Changes apply at
once.

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
- `returnConfirmsOnly` (default on): Return on an underlined word only confirms it. Off, it
  confirms and the app gets the Return too (a Japanese phrase is still only confirmed).
- `rightCommandPause` (default on): a right ⌘ tap pauses Seamtype in the text field (see **Pause** above).

Per-app behavior lives in `apps.json` next to it. `"*"` is your default for every app; an
app (by bundle identifier, a key ending in `.` matches as a prefix) changes only the keys it
names and follows the default for the rest. No app is listed unless you list it:

```json
{ "*":                     { "escapeToApp": true },
  "com.apple.Terminal":    { "conversionThreshold": 0.97 },
  "com.example.Game":      { "enabled": false } }
```

- `enabled` (default true): false passes every key through (plain English).
- `conversionThreshold` (default `0.5`): convert away from the typed letters only when at
  least this sure. `0.97` ("엄격하게", strict) keeps short shell commands from turning into
  Hangul in a terminal; `0.5` converts more Korean when you write prose.
- `escapeToApp` (default false): Esc goes to the app and ⇧Esc switches (for editors).

After editing these files by hand, restart the input method: `pkill -x Seamtype`.

## How it decides

Locally, in this order — a keystroke's preview takes at most ~3 ms, a word's final decision
~7 ms, even 70 letters into a phrase:

1. **Your corrections** (made twice, see Learning) always win (`lexicon.json`).
2. **Mixed words:** `githubdp` → `github에`, `UIrkxdmsrjs` → `UI같은건` when the front
   looks English (or is typed in capitals) and the end is a Korean particle or ending. Also a
   single letter, as in a variable name: `xdp` → `x에`, `Xfmf` → `X를`, though not `도`/`나`
   after a lowercase letter, which are common English endings (`heh`, `tsk`; a capital gives
   `X도`). `hellodnjfem` → `hello월드`, `githubtjqj` → `github서버` for a known English word (or a
   name typed with capitals) and a Korean word from the word lists (or, when the whole token spells
   nothing like English, any Hangul of common syllables). Korean then an English word,
   `dhsmfdmsgoogledptj` → `오늘은google에서`: the Korean goes in and the rest keeps composing.
   With Japanese on: `githubde` → `githubで` for a known English word plus one case particle, and
   Korean and Japanese typed together, `dlfurrireki` → `이력りれき` (Space for `履歴`),
   `rirekifmf` → `りれき를`, `kyouhaehtlfkrdms` → `きょうは도시락은` (the Japanese part is committed
   on the spot, so with live conversion it goes in as `履歴를`, `今日は도시락은`), only when the
   Korean side breaks, so ordinary Japanese phrases stay whole. These split in an app set to
   Strict too.
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

Download the installer [`Seamtype.pkg`](https://github.com/aimdevlee/seamtype/releases/latest/download/Seamtype.pkg), open it and follow the steps (Apple silicon and
Intel, notarized by Apple). It installs into `/Library/Input Methods` and registers the input source,
so you only need to pick Seamtype in the input menu in the menu bar.

If you use Terminal, one line installs into `~/Library/Input Methods` instead (no administrator
rights):

```sh
curl -fsSL https://raw.githubusercontent.com/aimdevlee/seamtype/main/scripts/get.sh | sh
```

`Seamtype.zip` on [Releases](https://github.com/aimdevlee/seamtype/releases) is notarized too, so
you can also download it in a browser, unzip it and move it into `~/Library/Input Methods`.

Or build from source (Xcode or the Command Line Tools, Swift 6.1 or later):

```sh
scripts/install.sh        # builds and self-tests Seamtype.app, installs it
```

If Seamtype isn't in the input menu, add it in **System Settings → Keyboard → Input Sources →
Edit… → + → Korean → Seamtype**, and if it isn't listed there, log out and back in once. The pkg
installs into `/Library/Input Methods` and the other ways into `~/Library/Input Methods`, so use
only one or you'd get two copies of the input method.

**Uninstall:** in the settings window, click **About → Uninstall Seamtype → Uninstall…**. It removes
Seamtype from both Input Methods folders (macOS asks for your password if you used the pkg) and
switches to another input source; settings and learned words go only if you tick that in the
confirmation. To do it in Terminal instead, remove Seamtype from the input sources, then:

```sh
pkill -x Seamtype
rm -rf ~/Library/Input\ Methods/Seamtype.app
rm -rf ~/Library/Application\ Support/Seamtype   # only to drop settings and learned words
```

If you installed the pkg, the app is in `/Library/Input Methods/Seamtype.app` (remove it with
`sudo rm -rf`, and its receipt with `sudo pkgutil --forget com.aimdevlee.inputmethod.Seamtype.pkg`).

Resources: ~50 MB of memory (plus the ~35 MB Japanese dictionary when Japanese is on), a
~47 MB app, nothing else running. Keystrokes never leave the input method.

## Develop

```sh
swift test                     # tests: composers, engines, sessions, settings, end to end
scripts/typing-test/run.sh     # real key events into TextEdit through the installed Seamtype
swift scripts/make-readme-logo.swift docs/media  # the README logo (animated SVG)
scripts/release.sh             # universal (arm64 + x86_64) zip and pkg for a release; with a Developer ID also signed and notarized (app and pkg)
tools/prepare.sh               # accuracy (downloads word lists, Tatoeba and SCOWL once)
tools/prepare.sh --models      # rebuild the data in Sources/SeamtypeCore/Data first (not korean_vocabulary.txt)
SEAMTYPE_TIMING=1 swift run -c release seamtype-cli --decide --japanese < keys.tsv  # + time per decision
swift run seamtype-cli -v "dkssud gksrmf hello"               # English/Korean, with scores
printf 'kyouhagoogledekensaku\t\n' | swift run seamtype-cli --decide --japanese
printf 'きょうはいいてんきですね\n' | swift run seamtype-cli --convert
```

| Path | What |
| --- | --- |
| `Sources/SeamtypeCore` | composers, engines, conversion, `InputSession` (all typing logic) |
| `Sources/Seamtype` | InputMethodKit server, a thin controller over `InputSession`, candidate window, settings window |
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
