import SeamtypeCore
import Cocoa
import InputMethodKit
import Carbon

// `Seamtype --settings [general|typing|apps|learning|about]`: the settings window, started from the input menu.
if let flag = CommandLine.arguments.firstIndex(of: "--settings") {
    let next = CommandLine.arguments.dropFirst(flag + 1).first
    MainActor.assumeIsolated { runSettingsApp(tab: next.flatMap(SettingsTab.init(rawValue:)) ?? .general) }
}

// `Seamtype --register`: register this bundle as an input method and enable its input source,
// for the user running it (the installer package runs it as the logged-in user). Recent macOS
// may still want the user to add it in System Settings → Keyboard → Input Sources.
if CommandLine.arguments.contains("--register") {
    let status = TISRegisterInputSource(Bundle.main.bundleURL as CFURL)
    let filter = [kTISPropertyInputSourceID as String: Bundle.main.bundleIdentifier ?? ""] as CFDictionary
    if status == noErr, let source = (TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource])?.first {
        TISEnableInputSource(source)
    }
    print(status == noErr ? "registered \(Bundle.main.bundlePath)" : "could not register (\(status))")
    exit(status == noErr ? 0 : 1)
}

// `Seamtype --selftest`: load every model from the bundle and exit (used by build-app.sh).
if CommandLine.arguments.contains("--selftest") {
    MainActor.assumeIsolated {
        var ok = true
        // A fresh engine: the user's learned words must not decide the self-test.
        let fresh = SplittingEngine(base: HeuristicEngine(), english: .shared)
        let english = fresh.decide("hello", context: DecisionContext()).language == .english
        let korean = fresh.decide("dkssud", context: DecisionContext()).output == "안녕"
        let lists = EnglishModel.shared.wordCount > 100_000 && KoreanModel().isKnownWord("나는")
        print("english/korean: \(english && korean && lists ? "ok" : "FAILED")")
        ok = ok && english && korean && lists
        // Must come from the bundle, not the source-tree fallback used in development.
        let resources = [Resources.kanaModel, Resources.textModel, Resources.englishWords, Resources.koreanWords,
                         Resources.koreanSyllables, Resources.japaneseDictionary]
        let bundled = resources.allSatisfy { $0?.path.hasPrefix(Bundle.main.bundlePath) == true }
        print("resources in bundle: \(bundled ? "ok" : "FAILED")")
        ok = ok && bundled
        // A throwaway memory folder: the self-test must not create or touch the user's.
        let memory = FileManager.default.temporaryDirectory.appendingPathComponent("seamtype-selftest-\(UUID().uuidString)")
        if let model = JapaneseModel.shared, let converter = AzooKeyConverter(memory: memory) {
            let kana = model.score(keys: "konnichiha") != nil
            let kanji = converter.candidates(for: "へんかん").contains { $0.text == "変換" }
            print("japanese model: \(kana ? "ok" : "FAILED"), dictionary: \(kanji ? "ok" : "FAILED")")
            ok = ok && kana && kanji
        } else {
            print("japanese resources: FAILED (not found in \(Bundle.main.resourceURL?.path ?? "?"))")
            ok = false
        }
        try? FileManager.default.removeItem(at: memory)
        exit(ok ? 0 : 1)
    }
}

let connectionName = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String
    ?? "com.aimdevlee.inputmethod.Seamtype_Connection"

guard let server = IMKServer(name: connectionName, bundleIdentifier: Bundle.main.bundleIdentifier) else {
    fatalError("Seamtype: could not start IMKServer '\(connectionName)'. Run from the installed .app bundle.")
}

// Build the language models (and load the Japanese dictionary) before the first keystroke.
MainActor.assumeIsolated {
    _ = Runtime.shared.engine.decide("warmup", context: DecisionContext())
    _ = Runtime.shared.converter?.candidates(for: "あ")
}

withExtendedLifetime(server) {
    NSApplication.shared.run()
}
