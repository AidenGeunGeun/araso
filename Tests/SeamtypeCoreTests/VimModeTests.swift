import Foundation
import Testing
@testable import SeamtypeCore

@Suite struct VimNormalModeTests {
    /// Feeds `keys` ("⏎" Return, "⎋" Esc) and returns the index of the key that started insert
    /// mode, or nil if vim is still in normal mode after all of them.
    func insertAt(_ keys: String) -> Int? {
        var vim = VimNormalMode()
        for (i, ch) in keys.enumerated() {
            switch ch {
            case "⏎": if vim.enter() { return i }
            case "⎋": vim.escape()
            default: if vim.feed(ch) { return i }
            }
        }
        return nil
    }

    @Test func commandsStayInNormalMode() {
        for keys in ["dd", "jjjk", "diw", "dap", "yiw", "fa", "Fi", "ta", "ri", "ra", "x", "p", "u", "5j", "d3w",
                     "gg", "G", "ma", "'a", "\"ayy", "\"ip", "qaq", "@a", "zz", ">>", "dgg", "dfa", "dta",
                     "viwd", "vipy", "Vjd", "vasx", "gUiw", "guu", "n", "*", ".", "J", "~"] {
            #expect(insertAt(keys) == nil, "\(keys)")
        }
    }

    @Test func insertModeKeys() {
        for keys in ["i", "a", "I", "A", "o", "O", "s", "S", "C", "R", "gi", "gI"] {
            #expect(insertAt(keys) == keys.count - 1, "\(keys)")
        }
    }

    @Test func changeStartsInsertAfterItsMotion() {
        #expect(insertAt("ciw") == 2)
        #expect(insertAt("cw") == 1)
        #expect(insertAt("cc") == 1)
        #expect(insertAt("c$") == 1)
        #expect(insertAt("cfa") == 2)
        #expect(insertAt("ci\"") == 2)
        #expect(insertAt("c2w") == 2)
        #expect(insertAt("\"acw") == 3)
        #expect(insertAt("viwc") == 3)
        #expect(insertAt("vjs") == 2)
    }

    @Test func commandLineGoesThroughUntilReturn() {
        #expect(insertAt(":w⏎") == nil)
        #expect(insertAt(":s/a/b/⏎i") == 8)
        #expect(insertAt("/iaos⏎") == nil)
        #expect(insertAt("/foo⏎a") == 5)
        #expect(insertAt(":wq⎋a") == 4) // Esc abandons the command line
    }

    @Test func escapeCancelsPendingKeys() {
        #expect(insertAt("d⎋i") == 2)
        #expect(insertAt("f⎋a") == 2)
        #expect(insertAt("v⎋i") == 2)
    }

    @Test func quittingEndsIt() {
        #expect(insertAt(":wq⏎") == 3)
        #expect(insertAt(":q!⏎") == 3)
        #expect(insertAt(":x⏎") == 2)
        #expect(insertAt("ZZ") == 1)
        #expect(insertAt("ZQ") == 1)
        #expect(insertAt(":w⏎dd") == nil)
        #expect(insertAt(":%s/q/x/⏎") == nil)
    }

    @Test func deleteEditsTheCommandLine() {
        var vim = VimNormalMode()
        for ch in ":wqq" { _ = vim.feed(ch) }
        vim.delete()
        let quit = vim.enter()
        #expect(quit)
        for ch in ":" { _ = vim.feed(ch) }
        vim.delete() // erasing the empty command line leaves it
        let inserted = vim.feed("i")
        #expect(inserted)
    }

    @Test func macroRecordingStopsWithoutAnArgument() {
        #expect(insertAt("qaddqi") == 5)
    }
}

/// A terminal set to "Esc: Vim", through a real session.
@MainActor @Suite struct VimSessionTests {
    let field = FakeTextField()
    let session: InputSession

    init() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("seamtype-vim-\(UUID().uuidString).json")
        let policies = AppPolicies(overrides: [
            "test.terminal": .init(conversionThreshold: AppPolicy.strictThreshold, escapeToApp: true, vim: true),
            "test.editor": .init(escapeToApp: true),
        ])
        session = InputSession(engine: LearningEngine(base: sharedEngine, storeURL: url), policies: policies)
        session.activate(app: "test.terminal")
    }

    /// Types `script` ("⎋" Esc, "⏎" Return, "⌫" Delete, "^" ⌃[) and returns what the app got
    /// straight from each key it was passed.
    @discardableResult
    func type(_ script: String) -> String {
        var passed = ""
        for ch in script {
            let key: InputSession.Key
            switch ch {
            case "⎋": key = .escape
            case "⏎": key = .enter
            case "⌫": key = .delete
            case "^": key = .leaveInsert
            case let c where c.isASCII && c.isLetter: key = .letter(c)
            default: key = .printable(ch)
            }
            if !session.handle(key, client: field) {
                passed.append(ch)
                if case .letter = key { field.insertText(String(ch), replacing: nil) }
                if case .printable = key { field.insertText(String(ch), replacing: nil) }
            }
        }
        return passed
    }

    @Test func normalModeKeysGoStraightThrough() {
        type("dkssud⎋")
        #expect(field.text == "안녕")
        #expect(type("ddjjciw") == "ddjjciw")
        #expect(field.marked.location == NSNotFound)
    }

    @Test func wordsAreDecidedAgainInInsertMode() {
        type("⎋o")
        type("dkssud ")
        #expect(field.text == "o안녕 ")
    }

    @Test func commandLineIsPassedWhole() {
        type("⎋")
        #expect(type(":w⏎") == ":w⏎")
        #expect(field.text == ":w")
        #expect(type("dd") == "dd")
    }

    @Test func quittingVimGivesTheShellWordsBack() {
        type("⎋")
        #expect(type(":wq⏎") == ":wq⏎")
        type("dkssud ")
        #expect(field.text.hasSuffix("안녕 "))
    }

    @Test func shiftEscStartsDecidingWordsAgain() {
        type("⎋")
        #expect(session.inVimNormalMode)
        #expect(session.handle(.cycle, client: field))
        #expect(!session.inVimNormalMode)
        type("dkssud ")
        #expect(field.text == "안녕 ")
    }

    @Test func controlBracketStartsNormalModeToo() {
        type("dkssud^")
        #expect(field.text == "안녕")
        #expect(type("dd") == "dd")
    }

    @Test func escInAnEditorWithoutVimStillComposesAfterwards() {
        session.activate(app: "test.editor")
        type("hello⎋")
        #expect(type("dkssud") == "")
        #expect(field.marked.location != NSNotFound)
    }

    @Test func comingBackToTheTerminalKeepsNormalMode() {
        type("⎋")
        session.activate(app: "test.terminal")
        #expect(type("dd") == "dd")
    }
}

@Suite struct VimPolicyTests {
    @Test func vimKeyInAppsJSON() throws {
        let entry = try JSONDecoder().decode(AppPolicy.Override.self, from: Data(#"{"vim": true}"#.utf8))
        let policy = entry.applied(to: .standard)
        #expect(policy.vim && policy.escapeGoesToApp && policy.escapeKey == .vim)
    }

    @Test func escapeKeyNamesBothStoredKeys() {
        var policy = AppPolicy()
        policy.escapeKey = .vim
        #expect(policy.escapeToApp && policy.vim)
        policy.escapeKey = .sendToApp
        #expect(policy.escapeToApp && !policy.vim)
        var entry = AppPolicy.Override(vim: true)
        #expect(entry.escapeKey == .vim)
        entry.escapeKey = nil
        #expect(entry == AppPolicy.Override())
    }
}
