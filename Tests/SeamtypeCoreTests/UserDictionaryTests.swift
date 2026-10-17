import Foundation
import Testing
@testable import SeamtypeCore

/// dictionary.json: corrected once nudges, twice wins, weak entries expire, lexicon.json moves in.
@Suite struct UserDictionaryTests {
    let dir: URL
    let day = Date(timeIntervalSince1970: 1_792_000_000)

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("seamtype-dict-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func days(_ n: Int) -> Date { day.addingTimeInterval(Double(n) * 86_400) }

    /// One correction only nudges: `so` (en −1.90, ko −2.00) turns, `hello` doesn't.
    @Test func onceNudgesACloseCallOnly() {
        let engine = DictionaryEngine(base: sharedEngine, storeURL: dir.appendingPathComponent("d.json"))
        #expect(engine.decide("so", context: DecisionContext()).language == .english)
        engine.learn("so", as: .korean, engineChoice: .english)
        #expect(engine.pending == ["so": .korean] && engine.learned.isEmpty)
        let so = engine.decide("so", context: DecisionContext())
        #expect(so.language == .korean && so.output == "내", "\(so.explanation)")
        // After an English word the previous word's pull and the nudge cancel out.
        #expect(engine.decide("so", context: DecisionContext(previousLanguage: .english)).language == .english)

        engine.learn("hello", as: .korean, engineChoice: .english)
        #expect(engine.decide("hello", context: DecisionContext()).language == .english)
        engine.learn("hello", as: .korean, engineChoice: .english)
        let hello = engine.decide("hello", context: DecisionContext())
        #expect(hello.language == .korean && hello.confidence == 1 && hello.explanation == "learned")
    }

    @Test func learningRules() {
        var dictionary = UserDictionary()
        let first = dictionary.learn("dlrjs", as: .korean, shown: .english, today: day)
        #expect(!first)
        #expect(dictionary.languageEntry(for: "dlrjs")?.strength == .weak)
        // Corrected to something else: weak for that one instead.
        dictionary.learn("dlrjs", as: .japanese, shown: .english, today: day)
        #expect(dictionary.languageEntry(for: "dlrjs")?.language == .japanese)
        #expect(dictionary.languageEntry(for: "dlrjs")?.strength == .weak)
        let second = dictionary.learn("dlrjs", as: .japanese, shown: .english, today: day)
        #expect(second)
        #expect(dictionary.languageEntry(for: "dlrjs")?.strength == .sure)
        // Back to what was shown without the entry: forgotten.
        dictionary.learn("dlrjs", as: .english, shown: .english, today: day)
        #expect(dictionary.entries.isEmpty)
        // Turned by a weak entry and switched away from it: forgotten.
        dictionary.learn("so", as: .korean, shown: .english, today: day)
        dictionary.learn("so", as: .english, shown: .korean, today: day)
        #expect(dictionary.entries.isEmpty)
        // A sentence switched as one token isn't learned.
        dictionary.learn("taxidnswjstndkwjTlkonnichiha", as: .korean, shown: .english, today: day)
        #expect(dictionary.entries.isEmpty)
    }

    @Test func wordsAddedByHandStay() {
        var dictionary = UserDictionary([
            .init(keys: "hoge", language: .japanese, source: .user),
            .init(keys: "rt", text: "감사합니다", source: .user),
        ])
        dictionary.learn("hoge", as: .english, shown: .japanese, today: day)
        dictionary.learn("hoge", as: .english, shown: .japanese, today: day)
        #expect(dictionary.languageEntry(for: "hoge")?.language == .japanese)
        dictionary.learn("rk", as: .korean, shown: .english, today: day)
        dictionary.forgetLearned()
        #expect(dictionary.entries.count == 2)
        // The text entry isn't a language: forgetting the keys leaves it.
        dictionary.forget("rt")
        dictionary.forget("hoge")
        #expect(dictionary.entries.map(\.keys) == ["rt"])
    }

    @Test func weakEntriesExpireUnlessUsed() {
        var dictionary = UserDictionary()
        dictionary.learn("so", as: .korean, shown: .english, today: day)
        dictionary.learn("rk", as: .korean, shown: .english, today: day)
        dictionary.learn("rk", as: .korean, shown: .english, today: day)
        dictionary.learn("gks", as: .korean, shown: .english, today: day)
        let used = dictionary.used("gks", as: .korean, today: days(20))
        let sameDay = dictionary.used("gks", as: .korean, today: days(20))
        let otherLanguage = dictionary.used("gks", as: .english, today: days(21))
        #expect(used && !sameDay && !otherLanguage)
        let early = dictionary.dropExpired(today: days(29))
        let month = dictionary.dropExpired(today: days(30))
        #expect(!early && month)
        // `so` went; the sure `rk` and the `gks` typed on day 20 stay.
        #expect(dictionary.entries.map(\.keys) == ["rk", "gks"])
    }

    @Test func savesAndReadsBack() throws {
        let url = dir.appendingPathComponent("dictionary.json")
        let engine = DictionaryEngine(base: sharedEngine, storeURL: url, today: { [day] in day })
        engine.learn("hello", as: .korean, engineChoice: .english)
        engine.learn("hello", as: .korean, engineChoice: .english)
        engine.learn("so", as: .korean, engineChoice: .english)
        let json = try String(contentsOf: url, encoding: .utf8)
        #expect(json.contains(#""as" : "korean""#) && json.contains(#""from" : "learned""#) && !json.contains("text"))
        let reloaded = DictionaryEngine(base: sharedEngine, storeURL: url, today: { [day] in day })
        #expect(reloaded.learned == ["hello": .korean] && reloaded.pending == ["so": .korean])
        // A month later the weak one is gone, also from the file.
        let later = DictionaryEngine(base: sharedEngine, storeURL: url, today: { [day] in day.addingTimeInterval(31 * 86_400) })
        #expect(later.pending.isEmpty && later.learned == ["hello": .korean])
        #expect(UserDictionary.decode(try Data(contentsOf: url))?.entries.count == 1)
    }

    @Test func lexiconMovesIn() throws {
        let legacy = dir.appendingPathComponent("lexicon.json")
        let url = dir.appendingPathComponent("dictionary.json")
        try Data(#"""
        {"learned": {"hoge": "japanese"},
         "once": {"chraork": "korean", "hoge": "english", "taxidnswjstndkwjTlkonnichiha": "korean"}}
        """#.utf8).write(to: legacy)
        let migrated = DictionaryEngine.migrate(from: legacy, to: url, today: day)
        #expect(migrated.entries.map(\.keys) == ["hoge", "chraork"])
        #expect(migrated.languageEntry(for: "hoge")?.strength == .sure)
        #expect(migrated.languageEntry(for: "chraork")?.strength == .weak)
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(FileManager.default.fileExists(atPath: legacy.appendingPathExtension("migrated").path))
        let engine = DictionaryEngine(base: sharedEngine, storeURL: url)
        #expect(engine.learned == ["hoge": .japanese])
    }
}
