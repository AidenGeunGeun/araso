import SeamtypeCore
import Cocoa
import SwiftUI

/// The user's dictionary (dictionary.json) as one list: words added here, words remembered
/// after two corrections, and words corrected once (which only lean that way, for a while).
struct DictionaryPane: View {
    @ObservedObject var model: SettingsModel
    @State private var filter = Filter.all
    @State private var search = ""
    @State private var selection = Set<UserDictionary.Entry.ID>()
    @State private var editing: EntrySheet.Target?
    @State private var confirmForgetAll = false
    @State private var confirmKanji = false

    enum Filter: Hashable, CaseIterable {
        case all, added, remembered, once

        func includes(_ entry: UserDictionary.Entry) -> Bool {
            switch self {
            case .all: return true
            case .added: return entry.source == .user
            case .remembered: return entry.strength == .sure
            case .once: return entry.strength == .weak
            }
        }

        var title: String {
            switch self {
            case .all: return L("All %ld")
            case .added: return L("Added %ld")
            case .remembered: return L("Remembered %ld")
            case .once: return L("Corrected once %ld")
            }
        }
    }

    private var shown: [UserDictionary.Entry] {
        model.entries.filter { entry in
            filter.includes(entry) && (search.isEmpty || entry.keys.localizedCaseInsensitiveContains(search)
                || EntryText.of(entry).localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Picker(L("List"), selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) { filter in
                        Text(String(format: filter.title, model.entries.filter(filter.includes).count)).tag(filter)
                    }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
                TextField(L("Search keys or words"), text: $search)
                    .textFieldStyle(.roundedBorder).frame(width: 180)
                Button { editing = .new(keys: "") } label: { Label(L("Add…"), systemImage: "plus") }
            }
            Text(L("These keys come out as written here, also with a particle after them. A word corrected once only leans that way, and is forgotten after 30 days unless you correct or type it again."))
                .font(.callout).foregroundStyle(.secondary)
            if shown.isEmpty {
                EmptyList(symbol: search.isEmpty ? "text.book.closed" : "magnifyingglass",
                          title: search.isEmpty ? L("No words yet") : L("No matches"),
                          detail: search.isEmpty ? L("Add a word with +, or switch a word that came out wrong with the language switch key: corrected the same way twice, it's remembered here.") : nil)
            } else {
                table
            }
            HStack {
                if model.settings.japanese {
                    Button(L("Reset Kanji Order…")) { confirmKanji = true }
                }
                Spacer()
                Button(L("Forget Learned Words…"), role: .destructive) { confirmForgetAll = true }
                    .disabled(!model.entries.contains { $0.source == .learned })
            }
        }
        .padding(20)
        .sheet(item: $editing) { EntrySheet(model: model, target: $0) }
        .confirmationDialog(L("Forget every learned word?"), isPresented: $confirmForgetAll) {
            Button(L("Forget All"), role: .destructive) { model.forgetAll() }
        } message: {
            Text(L("Words you added stay. This can't be undone."))
        }
        .confirmationDialog(L("Reset the kanji candidate order?"), isPresented: $confirmKanji) {
            Button(L("Reset"), role: .destructive) { model.resetKanji() }
        } message: {
            Text(L("Kanji you picked before won't come first anymore. Remembered words stay."))
        }
    }

    private var table: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(L("Keys")).frame(width: Column.keys, alignment: .leading)
                Text(L("Result")).frame(maxWidth: .infinity, alignment: .leading)
                Text(L("Source")).frame(width: Column.source, alignment: .leading)
                Text(L("Apps")).frame(width: Column.apps, alignment: .leading)
                Color.clear.frame(width: Column.actions, height: 1)
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 18).padding(.bottom, 4)
            List(selection: $selection) {
                ForEach(shown) { entry in
                    // The sheet chooses a reading: an entry of the user's own text isn't one, and
                    // saving it there would turn the text into a reading. It can only be removed.
                    EntryRow(entry: entry, model: model) { if entry.language != nil { editing = .edit(entry) } }
                        .tag(entry.id)
                        .contextMenu {
                            if entry.language != nil { Button(L("Edit…")) { editing = .edit(entry) } }
                            if entry.source == .learned { Button(L("Keep for Good")) { model.pin(entry.id) } }
                            Button(L("Remove"), role: .destructive) { model.remove(entry.id) }
                        }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .onDeleteCommand { selection.forEach(model.remove); selection = [] }
        }
    }
}

private enum Column {
    static let keys: CGFloat = 150
    static let source: CGFloat = 90
    static let apps: CGFloat = 130
    static let actions: CGFloat = 50
}

private struct EntryRow: View {
    let entry: UserDictionary.Entry
    @ObservedObject var model: SettingsModel
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: entry.keys).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle).help(entry.keys)
                .frame(width: Column.keys, alignment: .leading)
            HStack(spacing: 6) {
                Text(EntryText.kind(entry)).font(.callout).foregroundStyle(.secondary)
                Text(verbatim: EntryText.of(entry)).lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SourceBadge(entry: entry).frame(width: Column.source, alignment: .leading)
            Text(EntryText.apps(entry)).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                .frame(width: Column.apps, alignment: .leading)
            HStack(spacing: 6) {
                if entry.source == .learned {
                    Button { model.pin(entry.id) } label: { Image(systemName: "pin") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                        .help(L("Keep for good"))
                        .accessibilityLabel(L("Keep %@ for good", entry.keys))
                }
                Button { model.remove(entry.id) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.tertiary)
                    .help(L("Remove"))
                    .accessibilityLabel(L("Remove %@", entry.keys))
            }
            .frame(width: Column.actions, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: edit)
    }
}

/// How an entry reads in the list: its kind first (Korean, My text), then what it writes.
enum EntryText {
    static func kind(_ entry: UserDictionary.Entry) -> String {
        entry.language?.displayName ?? L("My text")
    }

    static func of(_ entry: UserDictionary.Entry) -> String {
        if let language = entry.language { return UserDictionary.reading(entry.keys, as: language) }
        return entry.text ?? ""
    }

    static func apps(_ entry: UserDictionary.Entry) -> String {
        if let days = UserDictionary.daysLeft(entry, today: Date()) { return L("%ld days left", days) }
        guard let apps = entry.apps else { return L("Every app") }
        return apps.map { $0.hasSuffix(".") ? $0 + "*" : AppName.of($0) }.joined(separator: ", ")
    }
}

private struct SourceBadge: View {
    let entry: UserDictionary.Entry

    var body: some View {
        let (title, color): (String, Color) = switch (entry.source, entry.strength) {
        case (.user, _): (L("Added"), .accentColor)
        case (_, .weak?): (L("Corrected once"), .orange)
        default: (L("Remembered"), .green)
        }
        Text(title).font(.caption)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
    }
}

/// Adds a word to the dictionary, or changes one: the keys as typed, the reading they come
/// out as, and the app they're for.
struct EntrySheet: View {
    enum Target: Identifiable {
        case new(keys: String)
        case edit(UserDictionary.Entry)

        var id: String {
            switch self {
            case .new(let keys): return "new:" + keys
            case .edit(let entry): return entry.id
            }
        }
    }

    @ObservedObject var model: SettingsModel
    let target: Target
    @State private var keys: String
    @State private var language: Language
    @State private var app: String?
    @Environment(\.dismiss) private var dismiss

    init(model: SettingsModel, target: Target) {
        self.model = model
        self.target = target
        switch target {
        case .new(let keys):
            _keys = State(initialValue: keys)
            _language = State(initialValue: .english)
            _app = State(initialValue: nil)
        case .edit(let entry):
            _keys = State(initialValue: entry.keys)
            _language = State(initialValue: entry.language ?? .english)
            _app = State(initialValue: entry.apps?.first)
        }
    }

    private var original: UserDictionary.Entry? {
        if case .edit(let entry) = target { return entry }
        return nil
    }

    /// The readings the keys have: Korean when they make Hangul, Japanese when it's on and
    /// they make kana.
    private var choices: [Language] {
        var choices: [Language] = [.english]
        if !keys.isEmpty, HangulComposer.compose(keys: keys) != nil { choices.append(.korean) }
        if model.settings.japanese || language == .japanese, !keys.isEmpty,
           RomajiComposer.compose(keys).strayLetters == 0 { choices.append(.japanese) }
        return choices
    }

    /// Apps set in apps.json and the ones running, by name.
    private var apps: [(id: String, name: String)] {
        var ids = Set(model.apps.map(\.id))
        for running in NSWorkspace.shared.runningApplications where running.activationPolicy == .regular {
            if let id = running.bundleIdentifier { ids.insert(id) }
        }
        if let app { ids.insert(app) }
        return ids.map { ($0, AppName.of($0)) }.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(original == nil ? L("Add to Dictionary") : L("Change Word")).font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                KeyField(keys: $keys).frame(height: 30)
                Text(L("Type the keys as you would on the English layout. They go in as typed, not through an input method."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Picker(L("Comes out as"), selection: $language) {
                ForEach(choices, id: \.self) { choice in
                    HStack(spacing: 8) {
                        Text(choice.displayName).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
                        Text(verbatim: keys.isEmpty ? "–" : UserDictionary.reading(keys, as: choice))
                        if choice == language, app == nil, !keys.isEmpty {
                            Text(L("— also with a particle: %@", Self.withParticle(keys, as: choice)))
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .tag(choice)
                }
            }
            .pickerStyle(.radioGroup)
            Picker(L("App"), selection: $app) {
                Text(L("Every app")).tag(String?.none)
                Divider()
                ForEach(apps, id: \.id) { app in Text(app.name).tag(String?.some(app.id)) }
            }
            .fixedSize()
            HStack {
                if let original {
                    Button(L("Remove"), role: .destructive) {
                        model.remove(original.id)
                        dismiss()
                    }
                }
                Spacer()
                Button(L("Cancel"), role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(original == nil ? L("Add") : L("Save")) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(keys.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onChange(of: keys) { _ in
            if !choices.contains(language) { language = .english }
        }
    }

    private func save() {
        guard !keys.isEmpty else { return }
        model.save(UserDictionary.Entry(keys: keys, language: language, source: .user, apps: app.map { [$0] }),
                   replacing: original)
        dismiss()
    }

    /// The word with a particle after it, as the dictionary splits it: 촉매에, ghostty에, ほげで.
    static func withParticle(_ keys: String, as language: Language) -> String {
        let word = UserDictionary.reading(keys, as: language)
        return word + (language == .japanese ? "で" : "에")
    }
}

/// Takes the keys themselves, not text: it isn't a text view, so no input method sees them.
/// Letters, `-` and `'` (⇧ for capitals), Delete to take one off.
private struct KeyField: NSViewRepresentable {
    @Binding var keys: String

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.keys = keys
        view.onChange = { keys = $0 }
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ view: KeyCaptureView, context: Context) {
        if view.keys != keys { view.keys = keys }
        view.onChange = { keys = $0 }
    }
}

final class KeyCaptureView: NSView {
    var keys = "" { didSet { label.stringValue = keys.isEmpty ? "" : keys; placeholder.isHidden = !keys.isEmpty } }
    var onChange: ((String) -> Void)?
    private let label = NSTextField(labelWithString: "")
    private let placeholder = NSTextField(labelWithString: L("Type the keys"))

    /// US-layout key codes, so the letters are the keys whatever the input source.
    static let qwerty: [UInt16: Character] = [
        0: "a", 11: "b", 8: "c", 2: "d", 14: "e", 3: "f", 5: "g", 4: "h", 34: "i", 38: "j", 40: "k",
        37: "l", 46: "m", 45: "n", 31: "o", 35: "p", 12: "q", 15: "r", 1: "s", 17: "t", 32: "u",
        9: "v", 13: "w", 7: "x", 16: "y", 6: "z", 27: "-", 39: "'",
    ]

    /// The key's letter: what it types when that is a letter, `-` or `'` (an English layout, as
    /// Seamtype's), else by its key code (a Korean layout types jamo).
    static func key(_ event: NSEvent) -> Character? {
        if let typed = event.charactersIgnoringModifiers?.lowercased(), typed.count == 1, let ch = typed.first,
           ch.isASCII, ch.isLetter || ch == "-" || ch == "'" {
            return ch
        }
        return qwerty[event.keyCode]
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        for field in [label, placeholder] {
            field.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
            field.translatesAutoresizingMaskIntoConstraints = false
            addSubview(field)
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                field.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
                field.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }
        label.lineBreakMode = .byTruncatingHead
        placeholder.textColor = .placeholderTextColor
        setAccessibilityRole(.textField)
        setAccessibilityLabel(L("Keys"))
        updateColors()
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; updateColors(); return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; updateColors(); return true }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    override func viewDidChangeEffectiveAppearance() { updateColors() }
    override func accessibilityValue() -> Any? { keys }

    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.isDisjoint(with: [.command, .control, .option]) else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 51, 117: // Delete, Forward Delete
            guard !keys.isEmpty else { return NSSound.beep() }
            keys.removeLast()
        case 48: // Tab
            flags.contains(.shift) ? window?.selectPreviousKeyView(self) : window?.selectNextKeyView(self)
            return
        default:
            guard var key = Self.key(event), keys.count < 40 else { return super.keyDown(with: event) }
            if flags.contains(.shift) { key = Character(key.uppercased()) }
            keys.append(key)
        }
        onChange?(keys)
    }
}
