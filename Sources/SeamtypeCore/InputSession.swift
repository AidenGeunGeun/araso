import Foundation

/// The text field the input method is typing into. Ranges are UTF-16, like NSString.
public protocol TextClient: AnyObject {
    func setMarkedText(_ text: String)
    /// `range == nil` replaces the marked text (or the selection if nothing is marked).
    func insertText(_ text: String, replacing range: NSRange?)
    func selectedRange() -> NSRange
    func markedRange() -> NSRange
    func text(in range: NSRange) -> String?
}

/// Per-client typing state: the word being composed, the language of the previous
/// word, the last committed word (so Esc right after a commit can change it), and
/// an in-progress kana→kanji conversion.
///
/// While a word is being composed:
///   letters        extend it; the underlined preview shows the likely language
///   Esc            cycle it: english → english+particle (github에) → korean → japanese
///                  (in terminals/editors Esc commits and goes to the app; ⇧Esc cycles)
///   ⇧Esc           cycle it, in every app
///   Delete         remove the last keystroke
///   Space          English/Korean: commit, then a space. Japanese: convert to kanji
///   , . ? ! - '    inside a Japanese phrase they are part of it (、。？！ー); otherwise
///                  they commit the word, then type the key
///   Return         Japanese: commit the kana as is. Otherwise commit and pass Return on
///   anything else  commit and let the app handle the key
/// While converting to kanji (candidate window open):
///   Space / ↓      next candidate          ↑      previous candidate
///   1–9            commit that candidate   Return commit the selected candidate
///   Esc / Delete   back to kana            letters/punctuation  commit, then keep typing
///   A candidate that covers only the start of the reading commits that part and
///   continues converting the rest.
/// Right after a word was committed with space/punctuation:
///   Esc / ⇧Esc     cycle that committed word the same way (⇧Esc only in terminals/editors).
///                  The same correction made twice is learned for good.
@MainActor
public final class InputSession {
    public enum Key: Equatable {
        case letter(Character)
        case delete
        case escape
        /// ⇧Esc: switch the word's language in every app, including those where Esc goes to the app.
        case cycle
        /// Space, digit or punctuation typed by the input method.
        case printable(Character)
        case enter
        case up
        case down
        /// ←/→: while converting, shorten or lengthen the first clause; otherwise like `other`.
        case left
        case right
        /// ⌃K / F7 and ⌃J / F6: the Japanese reading as katakana / hiragana.
        case katakana
        case hiragana
        /// Tab, ←/→, shortcuts…: commit and let the app handle the key.
        case other
    }

    /// A kana→kanji conversion in progress.
    public struct Conversion: Equatable {
        /// The reading still being converted.
        public let kana: String
        /// The romaji that produced `kana`, so Esc can go back to editing it.
        public let keys: String
        public let candidates: [ConversionCandidate]
        public var selected: Int
        /// The user chose Japanese for these keys with Esc (going back to kana keeps that).
        var userForced = false

        public var current: ConversionCandidate { candidates[selected] }
        /// What the user sees: the selected candidate, then any reading it doesn't cover.
        public var display: String { current.text + String(kana.dropFirst(current.kanaCount)) }
    }

    private struct Committed {
        let keys: String
        /// What Seamtype chose before any Esc.
        let decided: Language
        /// What it went in as (Esc after the commit changes `language`).
        let committedAs: Language
        let language: Language
        /// Exactly what was inserted: the word plus its boundary character.
        let text: String
        let boundary: String
        let location: Int
        let previous: Language?
    }

    public let engine: LearningEngine
    public let converter: JapaneseConverter?
    public var japaneseEnabled: Bool
    public private(set) var keys = ""
    public private(set) var app: String?
    public private(set) var policy = AppPolicy.standard
    public private(set) var conversion: Conversion?
    private let policies: AppPolicies
    private var forced: Language?
    /// Whether `forced` is the user's choice (Esc) rather than "back to kana" after converting
    /// a phrase the engine read as Japanese anyway: only the user's choices are corrections.
    private var forcedByUser = false
    /// The language the engine itself showed last, before any Esc: what a commit compares
    /// against, so a forced reading is never mistaken for the engine's own choice.
    private var enginePreview: Language?
    /// "henkan" came back from conversion as "henkan'" (the final n stays ん); dropped again
    /// if the word leaves Japanese, so English doesn't get an apostrophe nobody typed.
    private var addedNMarker = false
    private var previousLanguage: Language?
    private var lastCommit: Committed?
    /// The mode vim last reported (`vimChanged`), nil when no vim is reporting. In normal mode
    /// every key goes straight through; while vim reports at all, Esc is vim's.
    private var vimMode: VimSignal?
    /// The user paused Seamtype in this text field (a right ⌘ tap): keys go through as typed
    /// until the next tap or another text field.
    public private(set) var paused = false
    /// Language of the current preview, so in-phrase symbols know where they belong.
    private var previewLanguage: Language?
    /// The last key passed to the app was a digit (so "." there is a decimal point).
    private var afterDigit = false
    /// Live conversion: a Japanese phrase is shown as its top kanji candidate while it is typed,
    /// and committed that way.
    public let liveConversion: Bool
    /// Esc showed the current phrase's kana instead (the next Esc switches language as usual).
    private var liveSuppressed = false
    private var liveCache: (kana: String, candidate: ConversionCandidate?)?

    public init(engine: LearningEngine, policies: AppPolicies = AppPolicies(),
                converter: JapaneseConverter? = nil, japaneseEnabled: Bool = false, liveConversion: Bool = false) {
        self.engine = engine
        self.policies = policies
        self.converter = converter
        self.japaneseEnabled = japaneseEnabled
        self.liveConversion = liveConversion
        if japaneseEnabled, let model = JapaneseModel.shared {
            segmenter = JapaneseSegmenter(english: EnglishModel.shared, japanese: model)
        }
    }

    /// A new text field became active: pick its app's policy and forget the sentence context.
    public func activate(app bundleIdentifier: String?) {
        closeFlipWindow()
        // Coming back to the same terminal leaves vim in whatever mode it was.
        if bundleIdentifier != app { vimMode = nil }
        app = bundleIdentifier
        policy = policies.policy(for: bundleIdentifier)
        previousLanguage = nil
        paused = false
    }

    /// Pauses or resumes Seamtype in this text field; what was being typed goes in first.
    public func togglePause(client: TextClient?) {
        if !paused { commit(client: client) }
        paused.toggle()
        previousLanguage = nil
    }

    /// Vim's mode, from `Seamtype --vim` (the caller checks it came from this app).
    public func vimChanged(to signal: VimSignal, client: TextClient?) {
        if signal == .normal, vimMode != .normal {
            commit(client: client)
            previousLanguage = nil
        }
        vimMode = signal == .off ? nil : signal
    }

    /// Whether keys currently go straight to vim (normal, visual or command-line mode).
    public var inVimNormalMode: Bool { vimMode == .normal }

    /// Returns true when the key was consumed.
    public func handle(_ key: Key, client: TextClient) -> Bool {
        guard policy.enabled, !paused else { return false }
        if vimMode == .normal {
            // Vim's normal mode: every key is a command. ⇧Esc is the way out if vim's last word
            // was lost (Vim not seeing the terminal's focus change): it only says "decide words".
            if key == .cycle { vimMode = nil; return true }
            previousLanguage = nil
            return false
        }
        if conversion != nil { return handleConverting(key, client: client) }

        if case .printable = key, keys.isEmpty {} else { afterDigit = false }
        let pending = lastCommit
        lastCommit = nil
        // Esc switches languages unless the app owns it (or a reporting vim); ⇧Esc always does.
        let switchesLanguage = key == .cycle || (key == .escape && !policy.escapeToApp && vimMode == nil)
        if switchesLanguage, keys.isEmpty, let pending {
            if let changed = cycle(pending, client: client) {
                lastCommit = changed
                return true
            }
        }
        if let pending { finalize(pending) }

        switch key {
        case .letter(let ch):
            if keys.isEmpty { lastRecorded = nil; liveSuppressed = false } // a new word
            addedNMarker = false
            keys.append(ch)
            updatePreview(client)
            return true

        case .delete:
            guard !keys.isEmpty else { return false }
            keys.removeLast()
            addedNMarker = false
            if keys.isEmpty { forced = nil; forcedByUser = false }
            updatePreview(client)
            return true

        case .escape, .cycle:
            guard !keys.isEmpty else { return false }
            guard switchesLanguage else {
                // The app's Esc: the word goes in as shown, then the app gets the key.
                commit(client: client)
                return false
            }
            // A live-converted phrase goes back to its kana first.
            if isLive, (forced ?? previewLanguage) == .japanese {
                liveSuppressed = true
                updatePreview(client)
                return true
            }
            // Cycle from what the user sees.
            let shown = forced ?? previewLanguage ?? decide(partial: true).language
            forced = shown.next(for: keys, japanese: japaneseEnabled)
            forcedByUser = true
            if forced != .japanese { dropNMarker() }
            updatePreview(client)
            return true

        case .printable(let ch):
            if keys.isEmpty {
                defer { afterDigit = ch.isNumber }
                // After Japanese text, 、。？！ come out full-width like any Japanese IME
                // (but not inside a number: 3.5 stays 3.5).
                if previousLanguage == .japanese, !afterDigit, let full = Self.japanesePunctuation[ch] {
                    client.insertText(full, replacing: nil)
                    return true
                }
                return false
            }
            if japaneseEnabled, belongsToJapanesePhrase(ch) {
                keys.append(ch)
                updatePreview(client)
                return true
            }
            if ch == " ", currentLanguage() == .japanese, converter != nil {
                startConversion(client)
                return true
            }
            let marked = client.markedRange()
            let location = marked.location != NSNotFound ? marked.location : client.selectedRange().location
            let previous = previousLanguage
            let word = finishWord()
            // Only the word goes in; the app types the space or punctuation itself, as with the
            // system's Korean input. Handing over "word + space" for the space key made terminals
            // (Ghostty, which sends the key with its text) add a stray character.
            client.insertText(word.text, replacing: nil)
            lastCommit = Committed(keys: word.keys, decided: word.decided, committedAs: word.language,
                                   language: word.language, text: word.text + String(ch), boundary: String(ch),
                                   location: location, previous: previous)
            return false

        case .enter:
            guard !keys.isEmpty else { return false }
            let japanese = currentLanguage() == .japanese
            commit(client: client)
            return japanese // a Japanese IME's Return only confirms the text

        case .katakana, .hiragana:
            // Only for a Japanese phrase; otherwise ⌃K/⌃J stay the app's shortcuts.
            guard !keys.isEmpty, japaneseEnabled, forced == .japanese || previewLanguage == .japanese else {
                commit(client: client)
                return false
            }
            showKanaForms(key == .katakana, client: client)
            return true

        case .up, .down, .left, .right, .other:
            commit(client: client)
            previousLanguage = nil
            return false
        }
    }

    /// Commits whatever is in progress as-is (focus change, shortcut, deactivation).
    public func commit(client: TextClient?) {
        closeFlipWindow()
        if let conversion {
            client?.insertText(conversion.display, replacing: nil)
            converter?.learn(conversion.current, for: conversion.kana)
            self.conversion = nil
            keys = ""
            previousLanguage = .japanese
            return
        }
        guard !keys.isEmpty else { return }
        let word = finishWord()
        client?.insertText(word.text, replacing: nil)
    }

    /// Commits what's in progress after the caret was moved elsewhere (a click; the app asks):
    /// the next word doesn't continue the previous sentence.
    public func commitForNewContext(client: TextClient?) {
        commit(client: client)
        previousLanguage = nil
    }

    /// Commits candidate `index` of the open conversion (e.g. clicked in the candidate window).
    public func choose(_ index: Int, client: TextClient) {
        guard let conversion, conversion.candidates.indices.contains(index) else { return }
        self.conversion?.selected = index
        commitCandidate(client: client)
    }

    // MARK: - Japanese conversion

    static let japanesePunctuation: [Character: String] = [",": "、", ".": "。", "?": "？", "!": "！"]

    /// Whether a symbol typed after the current word continues a Japanese phrase.
    /// Sentence punctuation (、。？！) never changes the word's language: it joins only a
    /// word already read as Japanese ("hello." and "dho?" = 왜? stay what they were).
    /// The in-word marks ー and ' may also turn an English-looking start into Japanese
    /// ("ra" → "ra-" → らー), but never take a word away from Korean.
    private func belongsToJapanesePhrase(_ ch: Character) -> Bool {
        guard JapaneseModel.inPhraseSymbols.contains(ch) else { return false }
        if forced == .japanese || previewLanguage == .japanese { return true }
        // An English word before the mark keeps it English (to-do, co-op); ra-men isn't one.
        guard forced == nil, ch == "-" || ch == "'", previewLanguage == .english,
              !EnglishModel.shared.isKnownWord(keys),
              RomajiComposer.compose(keys, partial: true).strayLetters == 0 else { return false }
        let context = DecisionContext(previousLanguage: previousLanguage, partial: true)
        return engine.decide(keys + String(ch), context: context).language == .japanese
    }

    /// Splits English words out of a Japanese phrase (google in kyouhagoogledekensaku).
    public var segmenter: JapaneseSegmenter?

    /// Kana for the keys, with any English words inside the phrase kept as typed.
    private func japaneseReading(partial: Bool) -> String {
        if !partial, let segments = segmenter?.segment(keys) { return JapaneseSegmenter.text(segments) }
        // While typing, a consonant at the end is just waiting for its vowel (watashihag → わたしはg),
        // not a stray letter to split an English word ("hag") out of.
        if partial, RomajiComposer.compose(keys, partial: true).strayLetters > 0, let segments = segmenter?.segment(keys) {
            // While typing, the last segment may still be growing; keep its pending letters visible.
            return JapaneseSegmenter.text(segments.dropLast()) + {
                if case .japanese(let k, _) = segments.last! { return RomajiComposer.compose(k, partial: true).text }
                return JapaneseSegmenter.text([segments.last!])
            }()
        }
        return RomajiComposer.compose(keys, partial: partial).text
    }

    // MARK: - Live conversion

    private var isLive: Bool { liveConversion && !liveSuppressed && converter != nil }

    /// The top candidate covering all of `kana` (cached: the preview asks on every key).
    private func liveCandidate(for kana: String) -> ConversionCandidate? {
        if let cached = liveCache, cached.kana == kana { return cached.candidate }
        var candidate = converter?.candidates(for: kana).first { $0.kanaCount == kana.count }
        // A short reading only turns into kanji (私, 今日), not into katakana mid-word
        // (と → ト, こんに → コンに): those flicker while the phrase is still being typed.
        if kana.count <= 3, let c = candidate, !c.text.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) {
            candidate = nil
        }
        liveCache = (kana, candidate)
        return candidate
    }

    /// The Japanese phrase as shown while typing: kana, or with live conversion the top
    /// candidate followed by letters still waiting for their vowel (今日はいい天気でs).
    private func japaneseDisplay() -> String {
        let reading = japaneseReading(partial: true)
        guard isLive else { return reading }
        let pending = RomajiComposer.compose(keys, partial: true).pending
        guard reading.hasSuffix(pending) else { return reading }
        let kana = String(reading.dropLast(pending.count))
        guard !kana.isEmpty, let candidate = liveCandidate(for: kana) else { return reading }
        return candidate.text + pending
    }

    /// What a Japanese phrase commits as without the candidate window: the kana, or with
    /// live conversion the candidate that was on screen (which the converter learns).
    private func committedJapanese() -> String {
        let kana = japaneseReading(partial: false)
        guard isLive, let converter, let candidate = liveCandidate(for: kana) else { return kana }
        converter.learn(candidate, for: kana)
        return candidate.text
    }

    private func startConversion(_ client: TextClient) {
        let kana = japaneseReading(partial: false)
        guard let converter, !kana.isEmpty else { return }
        let userForced = forced == .japanese && forcedByUser
        if userForced {
            record(keys, as: .japanese, engineChoice: committedLanguage())
        }
        let candidates = converter.candidates(for: kana)
        guard !candidates.isEmpty else {
            commit(client: client)
            return
        }
        // With live conversion the top candidate is already on screen: Space shows the next one.
        var selected = 0
        if isLive, let live = liveCandidate(for: kana), let i = candidates.firstIndex(of: live), candidates.count > 1 {
            selected = (i + 1) % candidates.count
        }
        liveSuppressed = false
        conversion = Conversion(kana: kana, keys: keys, candidates: candidates, selected: selected, userForced: userForced)
        keys = ""
        forced = nil
        forcedByUser = false
        enginePreview = nil
        previousLanguage = .japanese
        client.setMarkedText(conversion!.display)
    }

    /// Shows the reading as katakana (or hiragana) as the selected "candidate": Return
    /// commits it, Space flips to the other form, typing on commits it and continues.
    private func showKanaForms(_ katakanaFirst: Bool, kana: String? = nil, keys romaji: String? = nil, client: TextClient) {
        let kana = kana ?? japaneseReading(partial: false)
        let forms = [ConversionCandidate(text: RomajiComposer.katakana(kana), kanaCount: kana.count),
                     ConversionCandidate(text: kana, kanaCount: kana.count)]
        conversion = Conversion(kana: kana, keys: romaji ?? keys, candidates: katakanaFirst ? forms : forms.reversed(), selected: 0)
        keys = ""
        forced = nil
        forcedByUser = false
        enginePreview = nil
        previousLanguage = .japanese
        client.setMarkedText(conversion!.display)
    }

    /// The conversion with its first clause `step` kana shorter or longer (今日は|いいてんき):
    /// candidates for exactly that much of the reading, the rest shown as kana. A boundary
    /// never falls inside an English word (google). Nil when it can't move further.
    private func resizeFirstClause(_ conversion: Conversion, by step: Int) -> Conversion? {
        guard let converter else { return nil }
        let reading = Array(conversion.kana)
        var length = conversion.current.kanaCount + step
        while (1..<reading.count).contains(length),
              reading[length - 1].isASCII, reading[length - 1].isLetter, reading[length].isASCII, reading[length].isLetter {
            length += step
        }
        guard (1...reading.count).contains(length), length != conversion.current.kanaCount else { return nil }
        let clause = String(reading[..<length])
        let candidates = converter.candidates(for: clause).filter { $0.kanaCount == clause.count }
        guard !candidates.isEmpty else { return nil }
        return Conversion(kana: conversion.kana, keys: conversion.keys, candidates: candidates, selected: 0,
                          userForced: conversion.userForced)
    }

    private func handleConverting(_ key: Key, client: TextClient) -> Bool {
        guard var conversion else { return false }
        switch key {
        case .printable(" "), .down:
            conversion.selected = (conversion.selected + 1) % conversion.candidates.count
            self.conversion = conversion
            client.setMarkedText(conversion.display)
            return true

        case .up:
            conversion.selected = (conversion.selected + conversion.candidates.count - 1) % conversion.candidates.count
            self.conversion = conversion
            client.setMarkedText(conversion.display)
            return true

        case .left, .right:
            if let resized = resizeFirstClause(conversion, by: key == .left ? -1 : 1) {
                self.conversion = resized
                client.setMarkedText(resized.display)
            }
            return true

        case .printable(let ch) where ch.isNumber:
            if let n = ch.wholeNumberValue, n >= 1, n <= min(9, conversion.candidates.count) {
                choose(n - 1, client: client)
                return true
            }
            commit(client: client)
            return handle(key, client: client)

        case .enter:
            commitCandidate(client: client)
            return true

        case .katakana, .hiragana:
            self.conversion = nil
            showKanaForms(key == .katakana, kana: conversion.kana, keys: conversion.keys, client: client)
            return true

        case .escape, .cycle, .delete:
            self.conversion = nil
            liveSuppressed = true // "back to kana" means kana, also with live conversion
            // Back to editing the romaji — when it still spells the reading. After part of a
            // phrase with English in it was committed it may not; keep the kana rather than lose it.
            guard JapaneseSegmenter.reading(of: conversion.keys, segmenter: segmenter) == conversion.kana else {
                client.insertText(conversion.kana, replacing: nil)
                previousLanguage = .japanese
                return true
            }
            // A final "n" was shown as ん; keep it ("henkan" → "henkan'") instead of
            // letting it wait for a vowel again.
            keys = conversion.keys
            if keys.hasSuffix("n"), !keys.hasSuffix("nn") { keys += "'"; addedNMarker = true }
            forced = .japanese
            forcedByUser = conversion.userForced
            updatePreview(client)
            return true

        case .letter, .printable:
            commit(client: client)
            return handle(key, client: client)

        case .other:
            commit(client: client)
            return false
        }
    }

    /// Commits the selected candidate; if it covers only the start of the reading,
    /// keeps converting the rest.
    private func commitCandidate(client: TextClient) {
        guard let conversion, let converter else { return }
        let candidate = conversion.current
        converter.learn(candidate, for: conversion.kana)
        client.insertText(candidate.text, replacing: nil)
        let rest = String(conversion.kana.dropFirst(candidate.kanaCount))
        self.conversion = nil
        guard !rest.isEmpty else { return }
        let restKeys = Self.keys(conversion.keys, after: candidate.kanaCount)
        let candidates = converter.candidates(for: rest)
        if candidates.isEmpty {
            client.insertText(rest, replacing: nil)
        } else {
            // The rest is the engine's Japanese, not something the user corrected.
            self.conversion = Conversion(kana: rest, keys: restKeys, candidates: candidates, selected: 0)
            client.setMarkedText(self.conversion!.display)
        }
    }

    /// The romaji left after the part that produced the first `kanaCount` kana: the
    /// shortest tail that composes to exactly the remaining kana ("kitte" after きっ is
    /// "te"; "konnichiha" after こん is "nichiha").
    static func keys(_ keys: String, after kanaCount: Int) -> String {
        let chars = Array(keys)
        let rest = String(RomajiComposer.compose(keys).text.dropFirst(kanaCount))
        for i in stride(from: chars.count, through: 0, by: -1) where RomajiComposer.compose(String(chars[i...])).text == rest {
            return String(chars[i...])
        }
        return ""
    }

    // MARK: - Private

    private func decide(partial: Bool) -> Decision {
        let d = engine.decide(keys, context: DecisionContext(previousLanguage: previousLanguage, partial: partial))
        let decision = d.language != .english && d.confidence < policy.conversionThreshold
            ? Decision(language: .english, confidence: 1 - d.confidence, output: keys,
                       explanation: String(format: "kept English (%.2f < %.2f); ", d.confidence,
                                           policy.conversionThreshold) + d.explanation)
            : d
        lastTrace = Trace(keys: keys, previous: previousLanguage, decision: decision, partial: partial)
        return decision
    }

    /// The last decision and what it was made from, for the settings window's typing test.
    public struct Trace: Sendable {
        public let keys: String
        public let previous: Language?
        public let decision: Decision
        /// Still being typed (the preview) rather than committed.
        public let partial: Bool
    }
    public private(set) var lastTrace: Trace?

    /// The language the current word will be committed in.
    private func currentLanguage() -> Language {
        forced ?? committedLanguage()
    }

    /// What Space/Return commits without Esc: the full-word decision, except that a hesitant
    /// change away from the reading on screen doesn't win (어떻게 shown, then "kept English"
    /// at 0.969 < 0.97 on Space). The same rule as the preview, so what you see is what you get.
    private func committedLanguage() -> Language {
        let d = decide(partial: false)
        if let shown = enginePreview, shown != d.language, !isWeakFlipAllowed(to: d, from: shown) {
            return shown
        }
        return d.language
    }

    /// Whether `decision` may replace the reading on screen: when it's confident, or when it's
    /// a dictionary English word (which is what Space/Return will commit).
    private func isWeakFlipAllowed(to decision: Decision, from shown: Language) -> Bool {
        decision.confidence >= Self.previewFlipConfidence
            || (decision.language == .english && EnglishModel.shared.isKnownWord(keys))
            || preview(as: shown) == nil
    }

    private func updatePreview(_ client: TextClient) {
        if keys.isEmpty {
            previewLanguage = nil
            enginePreview = nil
            client.setMarkedText("")
        } else if let forced {
            previewLanguage = forced
            client.setMarkedText(forced == .japanese ? japaneseDisplay() : engine.render(keys, as: forced))
        } else {
            splitOffKoreanBeforeOther(client)
            splitOffJapaneseBeforeKorean(client)
            let decision = decide(partial: true)
            var language = decision.language
            // Hysteresis: a weak flip on one keystroke (わた → "wat" → わたし) isn't shown,
            // except into a dictionary English word, which is what Space/Return will commit.
            if let shown = previewLanguage, shown != language, keys.count > 1, !isWeakFlipAllowed(to: decision, from: shown) {
                language = shown
            }
            previewLanguage = language
            enginePreview = language
            client.setMarkedText(language == .japanese ? japaneseDisplay() : preview(as: language) ?? keys)
        }
    }

    private static let koreanModel = KoreanModel()

    /// Korean with another language typed straight after it reads as broken Hangul: 이력 then
    /// rireki (dlfurrireki, 이력갹다ㅑ), 오늘은 then google에서 (dhsmfdmsgoogledptj, 오늘은해ㅐ힏에서).
    /// When the keys only make Hangul with stray jamo, but a front of two or more ordinary
    /// syllables is followed by a known English word (or one with a particle) or by romaji the
    /// engine is sure is Japanese, the Korean goes in as typed and the rest carries on as its own
    /// word (live conversion and Space for candidates when it's Japanese: 이력履歴).
    private func splitOffKoreanBeforeOther(_ client: TextClient) {
        guard keys.count >= 7,
              HangulComposer.compose(keys: keys)?.isBroken == true,
              // Only what reads as Korean on its own: a Japanese phrase whose start happens to
              // spell Hangul (chanwo…, 초무をころした) stays whole. Judged without context, since
              // right after Japanese everything leans Japanese.
              engine.decide(keys, context: DecisionContext(partial: true)).language == .korean else { return }
        let chars = Array(keys)
        for cut in 4...(chars.count - 3) {
            let front = String(chars[..<cut]), back = String(chars[cut...])
            guard let korean = HangulComposer.compose(keys: front), korean.strayJamo.isEmpty,
                  korean.syllables.count >= 2,
                  korean.syllables.allSatisfy({ Self.koreanModel.syllableLogProbability($0) > KoreanModel.unknownSyllableLogP }),
                  isOtherLanguageWord(back) else { continue }
            client.insertText(korean.text, replacing: nil)
            keys = back
            previousLanguage = .korean
            previewLanguage = nil
            enginePreview = nil
            return
        }
    }

    /// A known English word, one with a Korean particle (google에서), or romaji the engine is
    /// sure is Japanese (no word starts with っ or ん: that cut takes a letter from the Korean).
    private func isOtherLanguageWord(_ keys: String) -> Bool {
        let decision = engine.decide(keys, context: DecisionContext(previousLanguage: .korean, partial: true))
        switch decision.language {
        case .english: return keys.count >= 3 && EnglishModel.shared.isKnownWord(keys)
        case .mixed: return true
        case .japanese:
            guard japaneseEnabled, decision.confidence >= 0.9, keys.count >= 4 else { return false }
            let romaji = RomajiComposer.compose(keys, partial: true)
            return romaji.strayLetters == 0 && romaji.text.first.map { $0 != "っ" && $0 != "ん" } ?? false
        case .korean: return false
        }
    }

    /// Japanese with Korean typed straight after it reads as broken Hangul: a particle
    /// (rirekifmf, 履歴를, not 갹다ㅑ를) or a word (kyouhaehtl…, 今日は도시락은). Once the Korean
    /// part is a particle or two ordinary syllables, the Japanese goes in (kanji with live
    /// conversion) and the rest carries on as Korean, so 를요, 에서 or 도시락은 can follow.
    private func splitOffJapaneseBeforeKorean(_ client: TextClient) {
        guard japaneseEnabled, keys.count >= 5,
              HangulComposer.compose(keys: keys)?.isBroken ?? true,
              // Keys that still spell romaji are more Japanese (kyouhago is きょうはご, not きょうは해).
              RomajiComposer.compose(keys, partial: true).strayLetters > 0 else { return }
        let chars = Array(keys)
        // The longest Japanese front first: きょうは|도시, not きょう|하ㄷ….
        for cut in stride(from: chars.count - 1, through: 3, by: -1) {
            let front = String(chars[..<cut]), back = String(chars[cut...])
            guard back.first.map(DubeolsikLayout.startsSyllable) == true,
                  let korean = HangulComposer.compose(keys: back), korean.strayJamo.isEmpty,
                  MixedWord.suffixes.contains(korean.text)
                    || (korean.syllables.count >= 2
                        && korean.syllables.allSatisfy({ Self.koreanModel.syllableLogProbability($0) > KoreanModel.unknownSyllableLogP })),
                  RomajiComposer.compose(front).isClean,
                  case let decision = engine.decide(front, context: DecisionContext(previousLanguage: previousLanguage)),
                  decision.language == .japanese, decision.confidence >= 0.9 else { continue }
            keys = front
            client.insertText(committedJapanese(), replacing: nil)
            keys = back
            previousLanguage = .japanese
            forced = .korean
            forcedByUser = false
            previewLanguage = nil
            enginePreview = nil
            return
        }
    }

    /// The preview only switches language mid-word when the new reading is at least this likely.
    static let previewFlipConfidence = 0.7

    /// The word so far rendered in `language`, or nil when it has no such reading.
    private func preview(as language: Language) -> String? {
        switch language {
        case .english: return keys
        case .korean: return HangulComposer.compose(keys: keys)?.text
        case .mixed:
            let text = engine.render(keys, as: .mixed)
            return text == keys ? nil : text
        case .japanese: return japaneseEnabled ? japaneseReading(partial: true) : nil
        }
    }

    /// Decides the current word, learns an Esc override, and resets the buffer.
    private func finishWord() -> (keys: String, text: String, language: Language, decided: Language) {
        let engineChoice = committedLanguage()
        let language = forced ?? engineChoice
        if language != .japanese { dropNMarker() }
        // "Back to kana" without the user's Esc isn't a correction: report it as the engine's.
        let decided = forced != nil && !forcedByUser ? language : engineChoice
        if forced != nil, forcedByUser { record(keys, as: language, engineChoice: decided) }
        let text = language == .japanese ? committedJapanese() : engine.render(keys, as: language)
        liveSuppressed = false
        let word = (keys, text, language, decided)
        previousLanguage = language.sentenceLanguage
        keys = ""
        forced = nil
        forcedByUser = false
        addedNMarker = false
        previewLanguage = nil
        enginePreview = nil
        return word
    }

    private func dropNMarker() {
        if addedNMarker, keys.hasSuffix("'") { keys.removeLast() }
        addedNMarker = false
    }

    /// The last correction handed to the learning engine, for the word being typed or just
    /// committed: going back and forth (Space, Esc, Space while converting) is one correction.
    private var lastRecorded: (keys: String, language: Language)?

    private func record(_ keys: String, as language: Language, engineChoice: Language) {
        if let last = lastRecorded, last.keys == keys, last.language == language { return }
        lastRecorded = (keys, language)
        engine.learn(keys, as: language, engineChoice: engineChoice)
    }

    /// Replaces a just-committed word with its next rendering, but only if the caret
    /// still sits right after it and the text there is what we inserted.
    private func cycle(_ commit: Committed, client: TextClient) -> Committed? {
        let range = NSRange(location: commit.location, length: (commit.text as NSString).length)
        let cursor = client.selectedRange()
        guard cursor.location != NSNotFound, cursor.length == 0, cursor.location == NSMaxRange(range),
              client.text(in: range) == commit.text else { return nil }

        let language = commit.language.next(for: commit.keys, japanese: japaneseEnabled)
        let reading = language == .japanese ? JapaneseSegmenter.reading(of: commit.keys, segmenter: segmenter)
                                            : engine.render(commit.keys, as: language)
        let text = reading + commit.boundary
        client.insertText(text, replacing: range)
        previousLanguage = language.sentenceLanguage
        return Committed(keys: commit.keys, decided: commit.decided, committedAs: commit.committedAs,
                         language: language, text: text, boundary: commit.boundary, location: commit.location,
                         previous: commit.previous)
    }

    private func closeFlipWindow() {
        if let pending = lastCommit { finalize(pending) }
        lastCommit = nil
    }

    /// The undo window closed: learn where the word ended up (once, not every reading Esc
    /// passed through on the way).
    private func finalize(_ commit: Committed) {
        if commit.language != commit.committedAs {
            record(commit.keys, as: commit.language, engineChoice: commit.decided)
        }
    }
}
