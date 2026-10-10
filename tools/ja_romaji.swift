// Turns Japanese sentences into the romaji a person would type for them, using the
// macOS Japanese tokenizer's reading (it already spells particles as typed: は → ha,
// を → wo, へ → he). Normalizes the two places it differs from typing:
//   ~tsu (っ) → doubles the next consonant (待って: ma~tsu te → matte)
//   macron vowels from katakana ー → vowel + "-" (ラーメン: rāmen → ra-men)
//
// usage: swift ja_romaji.swift < sentences.txt > tokens.jsonl
// Each output line: {"text": "...", "tokens": [{"surface": "...", "romaji": "...", "latin": false}, ...]}
import Foundation

let macrons: [Character: String] = ["ā": "a-", "ī": "i-", "ū": "u-", "ē": "e-", "ō": "o-"]

func normalize(_ latin: String) -> String {
    var out = ""
    for ch in latin.lowercased() {
        if let m = macrons[ch] { out += m } else { out.append(ch) }
    }
    return out
}

struct Token: Encodable {
    let surface: String
    var romaji: String
    let latin: Bool
}

struct Line: Encodable {
    let text: String
    let tokens: [Token]
}

func tokens(_ text: String) -> [Token]? {
    let cf = text as CFString
    let tokenizer = CFStringTokenizerCreate(nil, cf, CFRange(location: 0, length: CFStringGetLength(cf)),
                                            kCFStringTokenizerUnitWord, Locale(identifier: "ja") as CFLocale)
    var out: [Token] = []
    while !CFStringTokenizerAdvanceToNextToken(tokenizer).isEmpty {
        let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
        let surface = (text as NSString).substring(with: NSRange(location: range.location, length: range.length))
        if surface.unicodeScalars.allSatisfy({ $0.isASCII }) {
            guard surface.allSatisfy({ $0.isLetter }) else { return nil } // digits etc.: skip sentence
            out.append(Token(surface: surface, romaji: surface.lowercased(), latin: true))
            continue
        }
        guard let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String
        else { return nil }
        out.append(Token(surface: surface, romaji: normalize(latin), latin: false))
    }
    // Resolve sokuon markers against the following token.
    for i in out.indices {
        var r = out[i].romaji
        while let range = r.range(of: "~tsu") {
            let rest = r[range.upperBound...]
            let next = rest.first ?? (i + 1 < out.count && !out[i + 1].latin ? out[i + 1].romaji.first : nil)
            if let next, "bcdfghjkmpqrstvwxz".contains(next) {
                r.replaceSubrange(range, with: String(next))
            } else {
                r.replaceSubrange(range, with: "xtu")
            }
        }
        r = r.replacingOccurrences(of: "~", with: "x") // remaining small kana: ~a → xa, ~ya → xya
        out[i].romaji = r
    }
    return out.isEmpty ? nil : out
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.withoutEscapingSlashes]
while let line = readLine() {
    let text = line.trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty, let t = tokens(text),
          t.allSatisfy({ $0.romaji.allSatisfy { $0.isASCII && ($0.isLetter || $0 == "-" || $0 == "'") } }) else { continue }
    print(String(decoding: try! encoder.encode(Line(text: text, tokens: t)), as: UTF8.self))
}
