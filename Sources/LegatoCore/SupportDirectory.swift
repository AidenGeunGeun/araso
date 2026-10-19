import Foundation

/// `~/Library/Application Support/Legato`: settings, per-app rules, learned words and
/// AzooKey's kanji learning. `LEGATO_SUPPORT_DIR` points a development copy (the settings
/// window, for screenshots) at another folder.
public enum SupportDirectory {
    public static var url: URL? {
        if let path = ProcessInfo.processInfo.environment["LEGATO_SUPPORT_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        _ = movedOnce
        return base.appendingPathComponent("Legato", isDirectory: true)
    }

    /// Once per process, before anything reads the folder. Only in the app (the input method and
    /// its settings window): the tests and legato-cli read the folder too, and moving it from
    /// under a Seamtype still installed would leave that one without its settings.
    private static let movedOnce: Void = {
        // Nor in a build's self-test, which runs the app on a machine that may have Seamtype.
        if Bundle.main.bundleIdentifier == "com.nyttastudio.inputmethod.Legato",
           !CommandLine.arguments.contains("--selftest"),
           let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            movePredecessor(in: base)
        }
    }()

    /// Seamtype (before 0.2.0) kept everything in `Application Support/Seamtype`: the first read
    /// after the update moves the folder, settings, dictionary and kanji learning alike. Left alone
    /// when `Legato` exists already, so nothing the user has under the new name is written over.
    static func movePredecessor(in base: URL) {
        let old = base.appendingPathComponent(Predecessor.supportFolder, isDirectory: true)
        let new = base.appendingPathComponent("Legato", isDirectory: true)
        let files = FileManager.default
        guard files.fileExists(atPath: old.path), !files.fileExists(atPath: new.path) else { return }
        try? files.moveItem(at: old, to: new)
    }

    /// Moves a file that can't be read (hand-edited, or from a newer version) to
    /// `<name>.unreadable`, so the next save doesn't write over what the user had.
    public static func setAside(_ url: URL) {
        let aside = url.appendingPathExtension("unreadable")
        try? FileManager.default.removeItem(at: aside)
        try? FileManager.default.moveItem(at: url, to: aside)
    }
}
