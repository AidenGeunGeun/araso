import Foundation
import Testing
@testable import SeamtypeCore

/// Live conversion with the real engines and the real AzooKey dictionary.
@MainActor @Suite struct LiveConversionTests {
    let field = FakeTextField()
    let session: InputSession

    init() throws {
        let dir = FileManager.default.temporaryDirectory
        let engine = LearningEngine(base: SplittingEngine(base: trilingual, english: trilingual.english, japanese: trilingual.segmenter),
                                    storeURL: dir.appendingPathComponent("seamtype-live-\(UUID().uuidString).json"))
        let converter = try #require(AzooKeyConverter(memory: dir.appendingPathComponent("seamtype-live-\(UUID().uuidString)")))
        session = InputSession(engine: engine, converter: converter, japaneseEnabled: true, liveConversion: true)
    }

    /// Letters and printable keys as themselves, "⏎" Return, "⎋" Esc.
    func type(_ script: String) {
        for ch in script {
            switch ch {
            case "⏎":
                if !session.handle(.enter, client: field) { field.insertText("\n", replacing: nil) }
            case "⎋": _ = session.handle(.escape, client: field)
            case let c where c.isLetter:
                if !session.handle(.letter(c), client: field) { field.insertText(String(c), replacing: nil) }
            default:
                if !session.handle(.printable(ch), client: field) { field.insertText(String(ch), replacing: nil) }
            }
        }
    }

    @Test func kanjiWhileTypingAndReturnCommitsThem() {
        type("kyouhaiitenkidesune")
        #expect(field.text == "今日はいい天気ですね") // still marked
        type("⏎")
        #expect(field.text == "今日はいい天気ですね")
        #expect(session.keys.isEmpty && session.conversion == nil)
    }

    @Test func lettersWaitingForAVowelStayVisible() {
        type("kyouhaiitenkides")
        #expect(field.text.hasPrefix("今日は"), "\(field.text)")
        #expect(field.text.hasSuffix("s"), "\(field.text)")
    }

    @Test func spaceShowsTheNextCandidate() {
        type("kyouhaiitenkidesune")
        let live = field.text
        type(" ")
        #expect(session.conversion != nil)
        #expect(field.text != live)
        type("⏎")
        #expect(session.conversion == nil)
        #expect(field.text.hasSuffix("ですね"))
    }

    @Test func escapeShowsKanaThenSwitchesLanguage() {
        type("kyouhaiitenkidesune⎋")
        #expect(field.text == "きょうはいいてんきですね")
        type("⎋")
        #expect(!field.text.contains("きょう"))
        type("⎋⎋⎋")
    }

    @Test func kanaCommitAfterEscape() {
        type("kyouhaiitenkidesune⎋⏎")
        #expect(field.text == "きょうはいいてんきですね")
    }

    @Test func otherLanguagesAreUnchanged() {
        type("dkssudgktpdy hello ")
        #expect(field.text == "안녕하세요 hello ")
    }

    @Test func englishInsidePhraseAndPunctuation() {
        type("kyouhagoogledekensaku⏎")
        #expect(field.text == "今日はgoogleで検索")
        type(" arigatou.⏎")
        #expect(field.text.hasSuffix("。"), "\(field.text)")
    }
}
