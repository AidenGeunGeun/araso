import SeamtypeCore
import Cocoa
import InputMethodKit
import os

private let log = Logger(subsystem: "com.aimdevlee.inputmethod.Seamtype", category: "input")

/// The candidate window shared by all controllers (one is visible at a time).
@MainActor var candidatesWindow: IMKCandidates?

/// Adapts InputMethodKit to `InputSession`, which holds all the typing logic.
@objc(SeamtypeInputController)
final class InputController: IMKInputController {
    private var current: (session: InputSession, generation: Int)?

    /// This client's session, rebuilt (after committing what was being typed) when a setting changed.
    @MainActor private var session: InputSession {
        let runtime = Runtime.shared
        if let current, current.generation == runtime.generation { return current.session }
        let fresh = runtime.makeSession()
        if let old = current?.session {
            old.commit(client: client().map { IMKClient($0 as IMKTextInput) })
            fresh.activate(app: old.app)
        }
        current = (fresh, runtime.generation)
        return fresh
    }

    private enum KeyCode {
        static let delete: UInt16 = 51
        static let escape: UInt16 = 53
        static let returnKey: UInt16 = 36
        static let keypadEnter: UInt16 = 76
        static let left: UInt16 = 123
        static let right: UInt16 = 124
        static let down: UInt16 = 125
        static let up: UInt16 = 126
        static let f6: UInt16 = 97
        static let f7: UInt16 = 98
    }

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        let client = sender as? IMKTextInput
        client?.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.US")
        let app = client?.bundleIdentifier()
        MainActor.assumeIsolated {
            Runtime.shared.active = self
            session.activate(app: app)
            if let signal = Runtime.shared.lastVimSignal { vimChanged(to: signal) }
            let policy = session.policy
            log.info("activate \(app ?? "?", privacy: .public) enabled=\(policy.enabled) threshold=\(policy.conversionThreshold) escapeToApp=\(policy.escapeToApp) vim=\(policy.vim)")
        }
    }

    /// Neovim changed mode (`Seamtype --vim`); it is in the text field this controller serves.
    @MainActor func vimChanged(to signal: VimSignal) {
        session.vimChanged(to: signal, client: client().map { IMKClient($0 as IMKTextInput) })
        log.debug("vim \(signal.rawValue, privacy: .public)")
    }

    override func deactivateServer(_ sender: Any!) {
        MainActor.assumeIsolated {
            session.commit(client: textInput(sender).map(IMKClient.init))
            candidatesWindow?.hide()
            Runtime.shared.converter?.save()
        }
        super.deactivateServer(sender)
    }

    override func commitComposition(_ sender: Any!) {
        MainActor.assumeIsolated {
            session.commitForNewContext(client: textInput(sender).map(IMKClient.init))
            candidatesWindow?.hide()
        }
    }

    /// The client to insert into: the sender, or this controller's own client when IMK passes
    /// none (so text being composed is never dropped on a focus change).
    private func textInput(_ sender: Any?) -> IMKTextInput? {
        (sender as? IMKTextInput) ?? client()
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown, let input = sender as? IMKTextInput else {
            log.debug("handle: not a key event from a text client")
            return false
        }
        return MainActor.assumeIsolated {
            let key = key(for: event)
            let handled = session.handle(key, client: IMKClient(input))
            syncCandidates()
            // The settings window's typing test shows how each word was decided; only there.
            if session.app == Bundle.main.bundleIdentifier, let trace = session.lastTrace {
                TypingTrace(trace).post()
            }
            // The kind of key only, never which character: typed text stays out of the log.
            log.debug("handle \(String(describing: key).prefix(while: { $0 != "(" }), privacy: .public) handled=\(handled) app=\(self.session.app ?? "?", privacy: .public)")
            return handled
        }
    }

    private func key(for event: NSEvent) -> InputSession.Key {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        if modifiers == .control {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "k": return .katakana
            case "j": return .hiragana
            case "[": return .leaveInsert // not ⌃C: at a shell prompt it would start vim's normal mode
            default: return .other
            }
        }
        if !modifiers.isEmpty { return .other }
        if event.keyCode == KeyCode.escape, event.modifierFlags.contains(.shift) { return .cycle }
        switch event.keyCode {
        case KeyCode.f7: return .katakana
        case KeyCode.f6: return .hiragana
        case KeyCode.delete: return .delete
        case KeyCode.escape: return .escape
        case KeyCode.returnKey, KeyCode.keypadEnter: return .enter
        case KeyCode.left: return .left
        case KeyCode.right: return .right
        case KeyCode.down: return .down
        case KeyCode.up: return .up
        default: break
        }
        guard let chars = event.characters, chars.unicodeScalars.count == 1,
              let ch = chars.first, let value = chars.unicodeScalars.first?.value else { return .other }
        if ch.isASCII && ch.isLetter { return .letter(ch) }
        if (0x20..<0x7F).contains(value) { return .printable(ch) }
        return .other
    }

    // MARK: - Candidate window

    @MainActor private func syncCandidates() {
        guard let conversion = session.conversion else {
            candidatesWindow?.hide()
            return
        }
        if candidatesWindow == nil {
            candidatesWindow = IMKCandidates(server: server(), panelType: kIMKSingleColumnScrollingCandidatePanel)
        }
        guard let window = candidatesWindow else { return }
        window.update()
        window.show(kIMKLocateCandidatesBelowHint)
        window.selectCandidate(withIdentifier: window.candidateIdentifier(atLineNumber: conversion.selected))
    }

    override func candidates(_ sender: Any!) -> [Any]! {
        MainActor.assumeIsolated { session.conversion?.candidates.map(\.text) ?? [] }
    }

    override func candidateSelected(_ candidateString: NSAttributedString!) {
        MainActor.assumeIsolated {
            guard let conversion = session.conversion, let text = candidateString?.string,
                  let index = conversion.candidates.firstIndex(where: { $0.text == text }),
                  let input: IMKTextInput = client() else { return }
            session.choose(index, client: IMKClient(input))
            syncCandidates()
        }
    }

    // MARK: - Input menu

    /// Seamtype's part of the input menu, built each time it opens.
    override func menu() -> NSMenu! {
        nonisolated(unsafe) var built: NSMenu?
        MainActor.assumeIsolated { built = buildMenu() }
        return built
    }

    @MainActor private func buildMenu() -> NSMenu {
        do {
            let runtime = Runtime.shared
            let menu = NSMenu()
            func add(_ title: String, _ action: Selector?, on: Bool = false, enabled: Bool = true,
                     indent: Int = 0, value: Any? = nil) {
                let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
                item.target = self
                item.state = on ? .on : .off
                item.isEnabled = enabled && action != nil
                item.indentationLevel = indent
                item.representedObject = value
                menu.addItem(item)
            }
            add(L("Japanese Input"), #selector(toggleJapanese(_:)), on: runtime.settings.japanese)
            add(L("Live Conversion"), #selector(toggleLiveConversion(_:)), on: runtime.settings.liveConversion,
                enabled: runtime.settings.japanese)

            if let app = current?.session.app ?? client()?.bundleIdentifier() {
                let policies = AppPolicies.load()
                let policy = policies.policy(for: app)
                let listed = policies.overrides[app] != nil
                menu.addItem(.separator())
                add(listed ? L("In %@ (app settings)", AppName.of(app)) : L("In %@ (default)", AppName.of(app)), nil)
                add(L("Strict — keeps commands intact"), #selector(setStrict(_:)), on: policy.conversionThreshold >= 0.9,
                    indent: 1, value: app)
                add(L("Normal — for writing Korean"), #selector(setNormal(_:)), on: policy.conversionThreshold < 0.9,
                    indent: 1, value: app)
                add(L("Esc Goes to the App (⇧Esc switches)"), #selector(toggleEscapeToApp(_:)), on: policy.escapeGoesToApp,
                    indent: 1, value: app)
                add(L("Vim: Commands Go Straight Through After Esc"), #selector(toggleVim(_:)), on: policy.vim,
                    indent: 1, value: app)
                add(L("Turn Off in This App"), #selector(toggleDisabled(_:)), on: !policy.enabled, indent: 1, value: app)
                if listed {
                    add(L("Remove App Settings — Use Default"), #selector(removeAppEntry(_:)), indent: 1, value: app)
                }
            }

            menu.addItem(.separator())
            if let keys = runtime.engine.lastLearned {
                add(L("Undo Last Learned (%@)", keys), #selector(undoLastLearned(_:)))
            }
            add(L("Try Typing…"), #selector(openTyping(_:)))
            add(L("Remembered Words…"), #selector(openLearned(_:)))
            add(L("Seamtype Settings…"), #selector(openSettings(_:)))
            return menu
        }
    }

    /// IMK hands menu actions a dictionary holding the item (or, on some versions, the item).
    private func menuItem(_ sender: Any?) -> NSMenuItem? {
        (sender as? [String: Any])?[kIMKCommandMenuItemName] as? NSMenuItem ?? sender as? NSMenuItem
    }

    private func appOf(_ sender: Any?) -> String? {
        if let app = menuItem(sender)?.representedObject as? String { return app }
        return MainActor.assumeIsolated { current?.session.app }
    }

    @objc func toggleJapanese(_ sender: Any?) {
        MainActor.assumeIsolated { Runtime.shared.update { $0.japanese.toggle() } }
    }

    @objc func toggleLiveConversion(_ sender: Any?) {
        MainActor.assumeIsolated { Runtime.shared.update { $0.liveConversion.toggle() } }
    }

    @objc func setStrict(_ sender: Any?) {
        guard let app = appOf(sender) else { return }
        MainActor.assumeIsolated { Runtime.shared.updatePolicy(for: app) { $0.conversionThreshold = AppPolicy.strictThreshold } }
    }

    @objc func setNormal(_ sender: Any?) {
        guard let app = appOf(sender) else { return }
        MainActor.assumeIsolated { Runtime.shared.updatePolicy(for: app) { $0.conversionThreshold = AppPolicy.standard.conversionThreshold } }
    }

    @objc func toggleEscapeToApp(_ sender: Any?) {
        guard let app = appOf(sender) else { return }
        MainActor.assumeIsolated {
            Runtime.shared.updatePolicy(for: app) { $0.escapeKey = $0.escapeGoesToApp ? .switchLanguage : .sendToApp }
        }
    }

    @objc func toggleVim(_ sender: Any?) {
        guard let app = appOf(sender) else { return }
        MainActor.assumeIsolated { Runtime.shared.updatePolicy(for: app) { $0.escapeKey = $0.vim ? .sendToApp : .vim } }
    }

    @objc func toggleDisabled(_ sender: Any?) {
        guard let app = appOf(sender) else { return }
        MainActor.assumeIsolated { Runtime.shared.updatePolicy(for: app) { $0.enabled.toggle() } }
    }

    @objc func removeAppEntry(_ sender: Any?) {
        guard let app = appOf(sender) else { return }
        MainActor.assumeIsolated { Runtime.shared.removePolicy(for: app) }
    }

    @objc func undoLastLearned(_ sender: Any?) {
        MainActor.assumeIsolated { Runtime.shared.undoLastLearned() }
    }

    @objc func openLearned(_ sender: Any?) { SettingsLauncher.open(tab: .learning) }
    @objc func openTyping(_ sender: Any?) { SettingsLauncher.open(tab: .typing) }
    @objc func openSettings(_ sender: Any?) { SettingsLauncher.open(tab: .general) }
}

/// `TextClient` over the IMK client proxy.
private final class IMKClient: TextClient {
    private let input: IMKTextInput
    private static let noRange = NSRange(location: NSNotFound, length: 0)

    init(_ input: IMKTextInput) { self.input = input }

    func setMarkedText(_ text: String) {
        let length = (text as NSString).length
        input.setMarkedText(text, selectionRange: NSRange(location: length, length: 0), replacementRange: Self.noRange)
    }

    func insertText(_ text: String, replacing range: NSRange?) {
        input.insertText(text, replacementRange: range ?? Self.noRange)
    }

    func selectedRange() -> NSRange { input.selectedRange() }
    func markedRange() -> NSRange { input.markedRange() }

    func text(in range: NSRange) -> String? {
        input.attributedSubstring(from: range)?.string
    }
}
