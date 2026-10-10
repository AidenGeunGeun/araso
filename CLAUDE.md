# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Seamtype is a macOS InputMethodKit input method: the user types on QWERTY and Seamtype decides per
word whether it is English, Korean (2-set) or Japanese romaji (kanji through AzooKey). README.md
(Korean, the main one) and README.en.md (English) cover the keys, settings files, accuracy numbers
and data licenses; read one before changing behavior users see, and keep both in step.

## Commands

```sh
swift build                                  # debug build of everything
swift test                                   # all tests (Swift Testing, ~7 s)
swift test --filter MixedWordTests           # one suite; --filter 'MixedWordTests/splitsEnglishPlusParticle' for one test
scripts/install.sh                           # release build + --selftest, install to ~/Library/Input Methods, enable, restart menu agent
scripts/release.sh                           # universal build → build/release/Seamtype{,-<version>}.zip and Seamtype-<version>.pkg
                                             # (SEAMTYPE_APP_SIGN / SEAMTYPE_PKG_SIGN / SEAMTYPE_NOTARY_PROFILE: Developer ID, notarization)
swift run seamtype-cli -v "dkssud hello"     # English/Korean decision with scores
printf 'keys\tprevious\n' | swift run seamtype-cli --decide --japanese   # previous: english|korean|japanese|empty
printf 'きょうは\n' | swift run seamtype-cli --convert                    # AzooKey candidates
tools/prepare.sh [--models]                  # held-out accuracy (downloads into tools/data, gitignored)
scripts/typing-test/run.sh                   # real key events into TextEdit through the installed app
scripts/record-demo/record.sh                # README demo GIF from real typing (also takes over the keyboard)
/usr/bin/log show --last 10m --predicate 'subsystem == "com.aimdevlee.inputmethod.Seamtype"' --info --debug
```

- `scripts/typing-test/run.sh` takes over the keyboard and focus for about a minute. Don't run it
  while the user is using the machine.
- Use `/usr/bin/log`, not `log`: zsh's builtin `log` shadows it and prints nothing.
- A change only reaches real typing after `scripts/install.sh`. A copy started with `open` or from
  `build/` never gets IMK connections; macOS has to launch the installed bundle itself.

## Architecture

**Targets.** `SeamtypeCore` holds all the typing logic and is what the tests cover. `Seamtype`
is a thin IMK layer over it. `seamtype-cli` is for tuning and evaluation.

**Decision chain** (built in `Runtime.makeEngine`): `LearningEngine` (lexicon.json: a correction
made twice wins) → `SplittingEngine` (`MixedWord.swift`) → `HeuristicEngine`.
- `SplittingEngine` handles English + Korean particle (`github에`), English + whole Korean word
  (`hello월드`, using `Data/korean_vocabulary.txt`, which is only for this) and English + Japanese
  particle (`githubで`).
- `HeuristicEngine` scores the keys per keystroke as English, Korean and Japanese, then nudges
  toward the previous word's language.
- `render(_:as: .mixed)` takes the engine's own decision output, so a split exists only if the
  engine produces it.

**`InputSession`** is one state machine per text client, behind the `TextClient` protocol (the
tests use `FakeTextField`). It owns the preview and hysteresis, commits, Esc reading cycling, the
"flip the word just committed" window, kana-kanji conversion and live conversion.
- Two splits happen here, not in the engine, because the Japanese half needs live conversion:
  Korean → Japanese (`이력` + `rireki`) and Japanese → Korean (`rireki` + `를`, `kyouha` + `도시락`).
  The Korean (or Japanese) part is committed mid-word and the rest keeps composing.
- They only fire when the keys spell neither clean Hangul nor clean romaji. The Korean → Japanese
  one also needs the whole token not to read as Japanese on its own. Without those guards, ordinary
  Japanese phrases split (`chanwokoroshita` → `초무をころした`).
- In an app set to "Esc: Vim" (`AppPolicy.vim`), Esc puts the session in vim's normal mode:
  `VimNormalMode` follows the keys (operators, text objects, `f`/`r` arguments, visual mode, the
  command line) and every key passes through until one enters insert mode.
- After a word ends with Space or punctuation, only the word is inserted and `handle` returns
  false, so the app types the key itself, as the system Korean IME does. Inserting "word + space"
  left a stray character in Ghostty. Test harnesses must insert the passed-on key themselves.

**`Runtime`** (`Sources/Seamtype`) is a process-wide singleton holding settings, engine and
converter, plus a `generation` counter. Controllers swap in a fresh session when the generation
changes, so a settings change applies without a restart.

**Settings window.** It is a separate process, `Seamtype --settings <tab>`, because the IME is
`LSBackgroundOnly`. It edits the JSON files in `~/Library/Application Support/Seamtype/` and posts
the distributed notification `com.aimdevlee.inputmethod.Seamtype.settingsChanged`; the IME reloads
on it.

**Per-app policy** (`AppPolicy.swift`): in `apps.json`, `"*"` is the user's default and an app
entry names only the keys that differ; a key ending in `.` matches as a prefix. There is no
built-in app list, so add an entry only when the user asks for one.

**Resources.** Data files are found by `Resources.swift`: `Contents/Resources` in the app, the
source tree in development. SPM resource bundles are avoided on purpose, because they'd sit outside
the signed `Contents`. `build-app.sh` copies each data file explicitly, so a new file under
`Sources/SeamtypeCore/Data` has to be added there too.

**Menu icon.** The system reads it from `Seamtype.tiff` (drawn by `scripts/make-icon.swift`),
and it's fixed: the bundle is signed (Developer ID for releases), so nothing inside it may change at
runtime.

## Conventions and pitfalls

- **Logging:** never log typed text. The input logger records the key kind and app only.
- **UI strings:** they go through `L("English key")`, with Korean in
  `Resources/ko.lproj/Localizable.strings`. The input source's name comes from
  `Resources/*.lproj/InfoPlist.strings`.
- **New split or heuristic rules:** check them for wrong splits, not just the target case.
  - Run every keys row of `tools/data/eval.tsv` (English, Korean, Japanese) through an
    `InputSession` with Japanese on, and count Hangul next to kana.
  - For English, also run `tools/data/en_50k.txt` through `seamtype-cli -v`.
  - The CLI only shows the engine's decision, so also test through a session: an earlier split
    looked right in the CLI but never reached real typing.
- **Install refreshes:** after a reinstall, the input menu keeps its old list until
  `TextInputMenuAgent` restarts (`install.sh` does this). A fresh process can still take 10–30 s
  to see the source as enabled, hence `enable-input-source.swift --check` with retries.
- **Releases** aren't Developer ID signed: users install with `scripts/get.sh` (curl, so no
  quarantine) from the release asset `Seamtype.zip`, which must keep that name for
  `releases/latest/download/Seamtype.zip`. `SEAMTYPE_ZIP=build/release/Seamtype.zip sh scripts/get.sh`
  tries it locally. The pkg installs into `/Library/Input Methods` and is not relocatable; its
  postinstall runs `Seamtype --register` as the logged-in user (users have no Swift toolchain, so
  registration can't use the scripts). The app is signed with the hardened runtime even ad hoc,
  and `build-app.sh` runs the self-test under Rosetta too for a universal build.
- **Stale registrations:** extra copies of the app registered with LaunchServices (`build/`,
  the old `AutoIME.app`) can make macOS launch the wrong one. `build-app.sh` unregisters its copy.
