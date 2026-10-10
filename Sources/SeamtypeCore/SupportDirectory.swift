import Foundation

/// `~/Library/Application Support/Seamtype`: settings, per-app rules, learned words and
/// AzooKey's kanji learning.
public enum SupportDirectory {
    public static var url: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Seamtype", isDirectory: true)
    }
}
