import Foundation

/// Legato was Seamtype until 0.2.0, under another bundle identifier: a different input method to
/// macOS. What an update from it has to find and clean up: its copies, its installer receipt, its
/// processes and its settings folder (moved by `SupportDirectory`).
public enum Predecessor {
    public static let bundleID = "com.aimdevlee.inputmethod.Seamtype"
    public static let appName = "Seamtype.app"
    public static let packageID = "com.aimdevlee.inputmethod.Seamtype.pkg"
    public static let supportFolder = "Seamtype"
}
