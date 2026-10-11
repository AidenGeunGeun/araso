import Foundation
import Testing
@testable import SeamtypeCore

/// Deterministic converter: a few readings with fixed candidates, including a
/// first-clause candidate to exercise partial commits.
@MainActor final class FakeConverter: JapaneseConverter {
    var learned: [String] = []
    func candidates(for kana: String) -> [ConversionCandidate] {
        switch kana {
        case "きょうはいいてんきですね":
            return [.init(text: "今日はいい天気ですね", kanaCount: 12), .init(text: "今日は", kanaCount: 4),
                    .init(text: kana, kanaCount: 12)]
        case "いいてんきですね":
            return [.init(text: "いい天気ですね", kanaCount: 8), .init(text: kana, kanaCount: 8)]
        case "へんかん":
            return [.init(text: "変換", kanaCount: 4), .init(text: "返還", kanaCount: 4), .init(text: "編纂", kanaCount: 4)]
        default:
            return [.init(text: kana, kanaCount: kana.count)]
        }
    }
    func learn(_ candidate: ConversionCandidate, for kana: String) { learned.append(candidate.text) }
    func save() {}
}

@MainActor @Suite struct JapaneseSessionTests {
    let field = FakeTextField()
    let converter = FakeConverter()
    let session: InputSession

    init() {
        let lex = FileManager.default.temporaryDirectory.appendingPathComponent("seamtype-ja-\(UUID().uuidString).json")
        let engine = LearningEngine(base: SplittingEngine(base: trilingual, english: trilingual.english, japanese: trilingual.segmenter), storeURL: lex)
        session = InputSession(engine: engine, converter: converter, japaneseEnabled: true)
    }

    func type(_ s: String) {
        // Keys the input method passes on are typed by the app, as in a real text field.
        for ch in s {
            let handled = ch.isLetter ? session.handle(.letter(ch), client: field) : session.handle(.printable(ch), client: field)
            if !handled { field.insertText(String(ch), replacing: nil) }
        }
    }

    @Test func previewShowsKanaWhileTyping() {
        type("kyouhaiitenk")
        #expect(field.text == "きょうはいいてんk")
    }

    @Test func spaceConvertsAndReturnCommits() {
        type("kyouhaiitenkidesune ")
        #expect(session.conversion != nil)
        #expect(field.text == "今日はいい天気ですね")
        #expect(session.handle(.enter, client: field))
        #expect(field.text == "今日はいい天気ですね")
        #expect(session.conversion == nil)
        #expect(converter.learned == ["今日はいい天気ですね"])
    }

    @Test func spaceCyclesCandidatesAndNumbersPick() {
        type("henkan ")
        #expect(field.text == "変換")
        type(" ")
        #expect(field.text == "返還")
        session.handle(.up, client: field)
        #expect(field.text == "変換")
        type("3")
        #expect(field.text == "編纂")
        #expect(session.conversion == nil)
    }

    @Test func firstClauseCandidateKeepsConvertingTheRest() {
        type("kyouhaiitenkidesune ")
        session.handle(.down, client: field) // 今日は (covers 4 kana)
        #expect(field.text == "今日はいいてんきですね")
        session.handle(.enter, client: field)
        #expect(field.text == "今日はいい天気ですね")
        #expect(session.conversion?.kana == "いいてんきですね")
        session.handle(.enter, client: field)
        #expect(session.conversion == nil)
        #expect(field.text == "今日はいい天気ですね")
    }

    @Test func escapeReturnsToKana() {
        type("henkan ")
        session.handle(.escape, client: field)
        #expect(session.conversion == nil)
        #expect(field.text == "へんかん")
        session.handle(.delete, client: field)
        #expect(field.text == "へんか")
    }

    @Test func deleteTakesOffAWholeKana() {
        type("kannkoku")
        #expect(field.text == "かんこく")
        session.handle(.delete, client: field)
        #expect(field.text == "かんこ")
        session.handle(.delete, client: field)
        #expect(field.text == "かん")
        type("ji ")
        #expect(converter.learned.isEmpty)
        #expect(session.conversion?.kana == "かんじ")
    }

    @Test func deleteKeepsAPendingLetterSeparate() {
        type("kannkok")
        #expect(field.text == "かんこk")
        session.handle(.delete, client: field)
        #expect(field.text == "かんこ")
    }

    @Test func deleteSplitsContractedAndDoubledKana() {
        type("kyouha")
        session.handle(.delete, client: field)
        session.handle(.delete, client: field)
        #expect(field.text == "きょ")
        session.handle(.delete, client: field)
        #expect(field.text == "き")
        type("tte")
        #expect(field.text == "きって")
        session.handle(.delete, client: field)
        #expect(field.text == "きっ")
        type("ta")
        #expect(field.text == "きった")
    }

    @Test func returnWithoutConvertingCommitsKanaOnly() {
        type("arigatou")
        #expect(field.text == "ありがとう")
        let consumed = session.handle(.enter, client: field)
        #expect(consumed) // a Japanese IME's Return only confirms the text
        #expect(field.text == "ありがとう")
    }

    @Test func previewMatchesWhatGetsCommitted() {
        // "kanji" is an English dictionary word: outside Japanese text it stays English,
        // and the preview says so before Return.
        type("kanji")
        #expect(field.text == "kanji")
        let consumed = session.handle(.enter, client: field)
        #expect(consumed) // Return only confirms, whatever the language
        #expect(field.text == "kanji")
        #expect(field.marked.location == NSNotFound)
    }

    @Test func punctuationStaysInsideJapanesePhrase() {
        type("arigatou.")
        #expect(field.text == "ありがとう。")
        type("ra-men")
        #expect(field.text == "ありがとう。らーめn") // ん waits for the next key, like any Japanese IME
    }

    /// After Japanese a symbol is full-width and underlined, as in a Japanese IME: Return only
    /// confirms it, the next letter starts a word of its own.
    @Test func symbolAfterJapaneseWaitsForReturn() {
        type("henkan ")
        session.handle(.enter, client: field)
        type("!?")
        #expect(field.text == "変換！？")
        #expect(field.marked.location != NSNotFound)
        #expect(session.handle(.enter, client: field))
        #expect(field.text == "変換！？")
        #expect(field.marked.location == NSNotFound)
        type("_")
        session.handle(.delete, client: field)
        #expect(field.text == "変換！？")
        type("/wo")
        #expect(field.text == "変換！？・を")
    }

    @Test func symbolAfterJapaneseConvertsWithSpace() {
        type("henkan ")
        session.handle(.enter, client: field)
        type("_ ")
        #expect(session.conversion?.kana == "＿")
    }

    @Test func numbersAfterJapaneseStayHalfWidth() {
        type("henkan ")
        session.handle(.enter, client: field)
        type("3.5:")
        #expect(field.text == "変換3.5:")
    }

    @Test func bracketsCloseTheWayTheyOpened() {
        type("henkan ")
        session.handle(.enter, client: field)
        type("(hello)")
        session.handle(.enter, client: field)
        #expect(field.text == "変換（hello）")
    }

    @Test func symbolsJoinOnlyAFinishedJapaneseWord() {
        type("nihon.")
        #expect(field.text == "にほん。")
    }

    @Test func symbolsInEnglishStayHalfWidth() {
        type("foo_bar (baz) a/b ")
        #expect(field.text == "foo_bar (baz) a/b ")
    }

    @Test func typingOnAfterConversionCommitsIt() {
        type("henkan ")
        type("wo")
        #expect(field.text == "変換を")
        #expect(session.conversion == nil)
    }

    @Test func englishAndKoreanStillWork() {
        type("hello dkssud ")
        #expect(field.text == "hello 안녕 ")
    }

    @Test func keysRemainderAfterKana() {
        #expect(InputSession.keys("kyouhaiitenki", after: 4) == "iitenki")
        #expect(InputSession.keys("kitte", after: 2) == "te")
        #expect(InputSession.keys("konnichiha", after: 2) == "nichiha")
    }
}

@MainActor @Suite struct TextReplacementTests {
    let field = FakeTextField()
    let converter = FakeConverter()
    let session: InputSession

    init() {
        let lex = FileManager.default.temporaryDirectory.appendingPathComponent("seamtype-tr-\(UUID().uuidString).json")
        let engine = LearningEngine(base: SplittingEngine(base: trilingual, english: trilingual.english, japanese: trilingual.segmenter), storeURL: lex)
        session = InputSession(engine: engine, policies: AppPolicies(overrides: [AppPolicies.defaultKey: .init(conversionThreshold: AppPolicy.strictThreshold)]),
                               converter: converter, japaneseEnabled: true)
        session.replacements = ["ㅈㅅ": "죄송합니다", "주소": "서울시", "よろ": "よろしくお願いします", "go": "gone"]
    }

    func type(_ s: String) {
        for ch in s {
            let handled = ch.isLetter ? session.handle(.letter(ch), client: field) : session.handle(.printable(ch), client: field)
            if !handled { field.insertText(String(ch), replacing: nil) }
        }
    }

    /// The shortcut goes in as typed, even in a Strict app, so the app can replace it on Space.
    @Test func koreanShortcutWinsTheDecision() {
        type("wt wnth ")
        #expect(field.text == "ㅈㅅ 주소 ")
    }

    @Test func japaneseShortcutIsTheFirstCandidate() {
        type("yoro ")
        #expect(session.conversion?.candidates.first?.text == "よろしくお願いします")
        session.handle(.enter, client: field)
        #expect(field.text == "よろしくお願いします")
    }

    @Test func englishShortcutsAreLeftToTheEngine() {
        type("kyouha go")
        #expect(session.lastTrace?.decision.explanation != "text replacement shortcut")
    }
}
