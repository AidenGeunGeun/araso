import Foundation

/// The user's dictionary, `dictionary.json`: keys typed as a whole word, and what they become.
///
///     [{ "keys": "cjrao", "as": "korean", "from": "learned", "strength": "weak", "last": "2026-10-17" },
///      { "keys": "hoge", "as": "japanese", "from": "user" }]
///
/// An entry is a language (`as`) or the user's own text (`text`, kept but not yet typed).
/// `from: user` entries were added by hand and stay until removed. `from: learned` ones come
/// from corrections with the switch key: corrected once they are `weak` and only nudge the
/// decision (and are dropped after `weakLifetime` days unused), corrected the same way again
/// they are `sure` and win.
public struct UserDictionary: Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public enum Source: String, Codable, Sendable { case user, learned }
        public enum Strength: String, Codable, Sendable { case weak, sure }

        public var keys: String
        public var language: Language?
        public var text: String?
        public var source: Source
        /// Learned entries only.
        public var strength: Strength?
        /// Nil: every app. Language entries limited to apps aren't used yet.
        public var apps: [String]?
        /// The day a learned entry was last corrected or typed (`yyyy-MM-dd`).
        public var last: String?

        enum CodingKeys: String, CodingKey {
            case keys, language = "as", text, source = "from", strength, apps, last
        }

        public init(keys: String, language: Language? = nil, text: String? = nil, source: Source,
                    strength: Strength? = nil, apps: [String]? = nil, last: String? = nil) {
            self.keys = keys
            self.language = language
            self.text = text
            self.source = source
            self.strength = source == .learned ? strength ?? .weak : nil
            self.apps = apps.flatMap { $0.isEmpty ? nil : $0 }
            self.last = last
        }

        /// A language entry that wins the decision: added by hand, or corrected twice.
        public var wins: Bool { language != nil && strength != .weak }
        var forEveryApp: Bool { apps == nil }
    }

    /// Days a weak entry lasts without being corrected or typed again.
    public static let weakLifetime = 30
    /// Longer tokens aren't learned: a sentence switched as one token isn't a word.
    public static let longestLearned = 20

    public private(set) var entries: [Entry]

    public init(_ entries: [Entry] = []) {
        self.entries = entries
    }

    /// The language entry for keys typed anywhere.
    public func languageEntry(for keys: String) -> Entry? {
        entries.first { $0.keys == keys && $0.language != nil && $0.forEveryApp }
    }

    /// Records that `keys` were corrected to `language` while `shown` was on screen.
    /// Returns true when the correction made the entry sure.
    ///
    /// - Back to what the engine showed: the learned entry goes (nothing to remember).
    /// - The same correction as the weak entry: sure.
    /// - Otherwise: a weak entry for `language`, replacing any learned one.
    /// Keys the user added by hand aren't changed by corrections.
    @discardableResult
    public mutating func learn(_ keys: String, as language: Language, shown: Language, today: Date) -> Bool {
        guard !keys.isEmpty, !entries.contains(where: { $0.keys == keys && $0.forEveryApp && $0.source == .user }) else { return false }
        let index = entries.firstIndex { $0.keys == keys && $0.forEveryApp && $0.source == .learned }
        let current = index.map { entries[$0] }
        if current?.language == language, current?.strength == .sure { return false }
        if language == shown {
            if let index { entries.remove(at: index) }
            return false
        }
        guard keys.count <= Self.longestLearned else { return false }
        let sure = current?.language == language
        let entry = Entry(keys: keys, language: language, source: .learned, strength: sure ? .sure : .weak,
                          last: Self.day(today))
        if let index { entries[index] = entry } else { entries.append(entry) }
        return sure
    }

    /// A weak entry's word went in as it says: it is still in use, so it stays.
    /// Returns true when something changed.
    public mutating func used(_ keys: String, as language: Language, today: Date) -> Bool {
        let day = Self.day(today)
        guard let index = entries.firstIndex(where: { $0.keys == keys && $0.forEveryApp && $0.strength == .weak }),
              entries[index].language == language, entries[index].last != day else { return false }
        entries[index].last = day
        return true
    }

    /// Removes the language entries for the keys (the engine decides them again).
    /// Returns true when something was removed.
    @discardableResult
    public mutating func forget(_ keys: String) -> Bool {
        let before = entries.count
        entries.removeAll { $0.keys == keys && $0.language != nil && $0.forEveryApp }
        return entries.count != before
    }

    /// Removes every learned entry; the user's own stay.
    public mutating func forgetLearned() {
        entries.removeAll { $0.source == .learned }
    }

    /// Drops weak entries not corrected or typed for `weakLifetime` days.
    public mutating func dropExpired(today: Date) -> Bool {
        let before = entries.count
        entries.removeAll { entry in
            guard entry.strength == .weak else { return false }
            guard let last = entry.last.flatMap(Self.date(_:)) else { return true }
            let days = Calendar.current.dateComponents([.day], from: last, to: today).day ?? 0
            return days >= Self.weakLifetime
        }
        return entries.count != before
    }

    // MARK: - Files

    public static func decode(_ data: Data) -> UserDictionary? {
        guard let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return nil }
        return UserDictionary(entries.filter { !$0.keys.isEmpty && ($0.language != nil || $0.text?.isEmpty == false) })
    }

    public func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(entries)
    }

    /// The entries of a lexicon.json from 0.1.16 and earlier (`learned`: corrected twice,
    /// `once`: corrected once), dated `today`. Nil when it can't be read.
    public static func migrating(lexicon data: Data, today: Date) -> UserDictionary? {
        struct Lexicon: Decodable {
            var learned: [String: Language] = [:]
            var once: [String: Language] = [:]
        }
        guard let lexicon = try? JSONDecoder().decode(Lexicon.self, from: data) else { return nil }
        let day = Self.day(today)
        let sure = lexicon.learned.sorted { $0.key < $1.key }.map {
            Entry(keys: $0.key, language: $0.value, source: .learned, strength: .sure, last: day)
        }
        let weak = lexicon.once.sorted { $0.key < $1.key }
            .filter { lexicon.learned[$0.key] == nil && $0.key.count <= longestLearned }
            .map { Entry(keys: $0.key, language: $0.value, source: .learned, strength: .weak, last: day) }
        return UserDictionary(sure + weak)
    }

    private static func formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = .current
        return formatter
    }

    static func day(_ date: Date) -> String { formatter().string(from: date) }
    static func date(_ day: String) -> Date? { formatter().date(from: day) }
}

/// Wraps an engine with the user's dictionary: a language entry that wins (added by hand,
/// or corrected the same way twice) decides the keys; a weak one (corrected once) passes
/// the base engine a nudge toward its language, so only a close call turns.
public final class DictionaryEngine: DecisionEngine, @unchecked Sendable {
    public let base: DecisionEngine
    private let lock = NSLock()
    private var store: UserDictionary
    private let storeURL: URL?
    private let today: @Sendable () -> Date

    public init(base: DecisionEngine, storeURL: URL? = DictionaryEngine.defaultStoreURL,
                today: @escaping @Sendable () -> Date = { Date() }) {
        self.base = base
        self.storeURL = storeURL
        self.today = today
        store = Self.read(storeURL, today: today())
    }

    public static var defaultStoreURL: URL? {
        SupportDirectory.url?.appendingPathComponent("dictionary.json")
    }

    /// lexicon.json of 0.1.16 and earlier, moved into dictionary.json the first time.
    public static var legacyStoreURL: URL? {
        SupportDirectory.url?.appendingPathComponent("lexicon.json")
    }

    private static func read(_ storeURL: URL?, today: Date) -> UserDictionary {
        guard let storeURL else { return UserDictionary() }
        if let data = try? Data(contentsOf: storeURL) {
            guard var saved = UserDictionary.decode(data) else {
                // Unreadable (hand-edited, or from a newer version): keep it aside, don't overwrite it.
                SupportDirectory.setAside(storeURL)
                return UserDictionary()
            }
            if saved.dropExpired(today: today) { write(saved, to: storeURL) }
            return saved
        }
        // Only the real file takes over lexicon.json: a test's or the CLI's store never does.
        guard storeURL == defaultStoreURL, let legacy = legacyStoreURL else { return UserDictionary() }
        return migrate(from: legacy, to: storeURL, today: today)
    }

    /// Moves lexicon.json's words into a new dictionary at `url` and renames it
    /// `lexicon.json.migrated`. An unreadable lexicon.json is set aside as before.
    @discardableResult
    public static func migrate(from legacy: URL, to url: URL, today: Date) -> UserDictionary {
        guard let data = try? Data(contentsOf: legacy) else { return UserDictionary() }
        guard var migrated = UserDictionary.migrating(lexicon: data, today: today) else {
            SupportDirectory.setAside(legacy)
            return UserDictionary()
        }
        _ = migrated.dropExpired(today: today)
        write(migrated, to: url)
        let done = legacy.appendingPathExtension("migrated")
        try? FileManager.default.removeItem(at: done)
        try? FileManager.default.moveItem(at: legacy, to: done)
        return migrated
    }

    public var dictionary: UserDictionary { lock.withLock { store } }
    /// Language entries that win: keys → language.
    public var learned: [String: Language] {
        lock.withLock { words(store.entries.filter { $0.wins && $0.apps == nil }) }
    }
    /// Words corrected once: the same correction again makes them sure.
    public var pending: [String: Language] {
        lock.withLock { words(store.entries.filter { $0.strength == .weak && $0.apps == nil }) }
    }
    /// The keys most recently made sure in this process, while still sure.
    public var lastLearned: String? {
        lock.withLock { lastLearnedKeys.flatMap { store.languageEntry(for: $0)?.strength == .sure ? $0 : nil } }
    }
    private var lastLearnedKeys: String?

    private func words(_ entries: [UserDictionary.Entry]) -> [String: Language] {
        Dictionary(entries.compactMap { entry in entry.language.map { (entry.keys, $0) } }, uniquingKeysWith: { first, _ in first })
    }

    /// Re-reads dictionary.json (after the settings window changed it).
    public func reload() {
        let fresh = Self.read(storeURL, today: today())
        lock.withLock { store = fresh }
    }

    /// Forgets the keys' language, learned or added: the engine decides them again.
    public func forget(_ keys: String) {
        persist(lock.withLock { store.forget(keys) ? store : nil })
    }

    /// Forgets every learned word; words the user added stay.
    public func forgetAll() {
        persist(lock.withLock {
            store.forgetLearned()
            return store
        })
    }

    public func decide(_ keys: String, context: DecisionContext) -> Decision {
        let entry = lock.withLock { store.languageEntry(for: keys) }
        if let entry, entry.wins, let language = entry.language {
            // Rendered by the base engine: this engine's own render(.mixed) would ask it to
            // decide the keys again, find them in the dictionary, and so on without end.
            return Decision(language: language, confidence: 1, output: base.render(keys, as: language),
                            explanation: entry.source == .user ? "added" : "learned")
        }
        var context = context
        if let entry, entry.strength == .weak { context.nudge = entry.language }
        return base.decide(keys, context: context)
    }

    /// Records that `keys` were corrected to `language`: once is weak, the same again sure,
    /// back to the engine's choice forgets the word.
    ///
    /// Pass `engineChoice` when the caller already knows what was shown (the input method
    /// always does: a fresh decision might not match).
    public func learn(_ keys: String, as language: Language, engineChoice: Language? = nil) {
        let shown = engineChoice ?? decide(keys, context: DecisionContext()).language
        let day = today()
        persist(lock.withLock {
            let before = store
            if store.learn(keys, as: language, shown: shown, today: day) { lastLearnedKeys = keys }
            return store == before ? nil : store
        })
    }

    /// The word went in as `language` without a correction: a weak entry saying so stays.
    public func used(_ keys: String, as language: Language) {
        let day = today()
        persist(lock.withLock { store.used(keys, as: language, today: day) ? store : nil })
    }

    private func persist(_ snapshot: UserDictionary?) {
        guard let snapshot, let url = storeURL else { return }
        Self.write(snapshot, to: url)
    }

    private static func write(_ dictionary: UserDictionary, to url: URL) {
        guard let data = dictionary.encoded() else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
