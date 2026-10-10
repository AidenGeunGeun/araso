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
        #expect(field.text == "へんかn")
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
        #expect(!consumed)
        #expect(field.text == "kanji")
    }

    @Test func punctuationStaysInsideJapanesePhrase() {
        type("arigatou.")
        #expect(field.text == "ありがとう。")
        type("ra-men")
        #expect(field.text == "ありがとう。らーめn") // ん waits for the next key, like any Japanese IME
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
