# Keyboard layouts

Araso decides per word between English, Korean and Japanese from the keys typed. Until 0.2.2 it
assumed QWERTY for English and romaji and 2-set (두벌식) for Korean. This is how other layouts fit.

## English layouts (done: Colemak, Colemak-DH)

`settings.json`'s `"latinLayout"`: `"qwerty"` (default), `"colemak"` or `"colemakDH"`; the
Languages pane's English layout menu.

**Keys are the layout's letters.** On Colemak `hello` is typed as `hello`, so English, romaji and
everything that reads keys as text (the English model, `RomajiComposer`, URL runs, the
dictionary's English entries) take them as they are.

**Korean looks through to the key.** 2-set Korean sits on QWERTY's letter keys whatever layout the
letters come from, as macOS's own 2-set does. `DubeolsikLayout` turns each key into its QWERTY
seat (`LatinLayout.seat(of:)`) before it asks for a jamo, a Shift double consonant or the
English-only capital check, so 안녕 on Colemak is `serrls` (the d k s s u d keys). That is the
one place Korean reads keys: `HangulComposer`, `MixedWord`, `ParticleSplitter`, `KoreanModel` and
the dictionary's Korean readings all go through it.

**The keys come from the key code.** With a layout other than QWERTY, `InputController` maps the
key code through the layout's rows itself (`LatinLayout.character(keyCode:shift:capsLock:)`), so the
setting decides, not whichever layout macOS hands the input method. A key is part of a word when
the layout types a letter on it or it is one of QWERTY's letter keys (2-set has a jamo there):
Colemak's `;` on the p key is 2-set's ㅔ and keeps the word composing.

**Where the layout comes from.** `LatinLayout.active`, set by `Runtime` from the settings (the
settings window's change reaches it through the usual notification). A test or tool overrides it
for its own task with `LatinLayout.$override.withValue(.colemak) { … }`; `araso-cli` takes
`ARASO_LAYOUT=colemak`.

**QWERTY is unchanged**: a key and its seat are the same character there.

**Accuracy** (eval.tsv, 5,998 held-out words and phrases, Japanese on; Korean rows rewritten to
each layout's letters with `tools/layout_eval.py`, English and Japanese rows are the same letters):

| layout | accuracy | English → Korean | Korean → English |
|---|---|---|---|
| QWERTY | 99.47% | 5 | 4 |
| Colemak | 99.35% | 9 | 7 |
| Colemak-DH | 99.33% | 9 | 8 |

The difference is which English words land on keys that spell real Hangul: on Colemak `git` is on
the t l f keys (실), `ti` on f l (리), `wes` on w k d (장). The weights were tuned on QWERTY's
collisions; Colemak's are a different set of about the same size. A word that keeps coming out
wrong is fixed the usual way: switched twice, the dictionary keeps it.

**What doesn't carry over.** The dictionary stores keys as typed, so words learned on one layout
don't match on another (their keys differ).

**Typing test.** `scripts/typing-test/colemak.tsv` runs on Colemak through the installed app; its
scripts are the QWERTY keys pressed (`hkuu;` for hello), so the key-code path is covered too.

## Dvorak (not done)

Dvorak puts `'`, `,`, `.` and `;` on the keys of 2-set's ㅂ, ㅈ, ㄷ and ㅋ. On those keys a word
would have to end (English punctuation) and keep composing (Korean jamo) at once. Needs a rule
for trailing punctuation keys: split them off when the word before reads well without them and
the jamo would leave broken Hangul (안녕. not 안녕ㄷ), with its own evaluation, including common
cases like `가.` where the jamo makes a valid syllable (갇).

## 세벌식 최종 (not done)

3-set has separate keys for initial, medial and final jamo, so no 도깨비불, and it types jamo on
digit and punctuation keys. Needs:

- a `KoreanLayout` setting next to `latinLayout`, and a 3-set composer beside `HangulComposer`
  (`DubeolsikLayout` becomes one implementation of a layout protocol);
- the word-boundary rule above, for digits and punctuation that are jamo in Korean;
- `KoreanModel` divides by the number of keys, and 3-set types more keys per syllable, so the
  Korean scores and thresholds need retuning;
- eval.tsv's Korean rows rewritten as 3-set keys (`tools/make_eval.py` has the 2-set table).
