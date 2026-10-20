import Foundation

/// The user's language for `key`: English is the key itself, Korean comes from
/// Resources/ko.lproj/Localizable.strings.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// `L` with `%@`/`%d` arguments filled in.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: arguments)
}
