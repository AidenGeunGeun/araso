// Types test scripts into a fresh TextEdit document with real key events (so they go
// through the selected input method) and compares the document text with the expectation.
//
// usage: typer <cases.tsv>    each line: script<TAB>expected
// script: characters as typed; ⏎ Return, ⎋ Esc, ⇧ Shift+Esc, ⌫ Delete, ← → arrows.
import AppKit
import Carbon

let keyCodes: [Character: (CGKeyCode, Bool)] = {
    var m: [Character: (CGKeyCode, Bool)] = [:]
    let lower: [Character: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
        "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38,
        "k": 40, "n": 45, "m": 46,
    ]
    for (c, k) in lower {
        m[c] = (k, false)
        m[Character(c.uppercased())] = (k, true)
    }
    let digits: [Character: CGKeyCode] = ["1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29]
    for (c, k) in digits { m[c] = (k, false) }
    m[" "] = (49, false); m[","] = (43, false); m["."] = (47, false); m["/"] = (44, false); m["?"] = (44, true)
    m["!"] = (18, true); m["-"] = (27, false); m["'"] = (39, false)
    m["⏎"] = (36, false); m["⎋"] = (53, false); m["⇧"] = (53, true); m["⌫"] = (51, false)
    m["←"] = (123, false); m["→"] = (124, false)
    return m
}()

func press(_ ch: Character) {
    guard let (code, shift) = keyCodes[ch] else { fatalError("no key for \(ch)") }
    let source = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)!
        e.flags = shift ? .maskShift : []
        e.post(tap: .cghidEventTap)
        usleep(12_000)
    }
    // Conversion (Space/Return in Japanese) and word commits take a moment.
    usleep(ch == " " || ch == "⏎" ? 250_000 : 45_000)
}

@discardableResult
func appleScript(_ source: String) -> String? {
    var error: NSDictionary?
    let result = NSAppleScript(source: source)!.executeAndReturnError(&error)
    if let error { FileHandle.standardError.write("AppleScript: \(error)\n".data(using: .utf8)!) }
    return result.stringValue
}

let cases = try! String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
    .split(separator: "\n").map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }

// Type through Seamtype for the run, then give back whatever input source was selected.
func sourceID(_ s: TISInputSource) -> String {
    guard let p = TISGetInputSourceProperty(s, kTISPropertyInputSourceID) else { return "" }
    return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
}
let previousSource = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
let sources = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
guard let seamtype = sources.first(where: { sourceID($0) == "com.aimdevlee.inputmethod.Seamtype" }) else {
    fatalError("Seamtype is not an enabled input source (System Settings → Keyboard → Input Sources)")
}

appleScript("tell application \"TextEdit\" to make new document")
appleScript("tell application \"TextEdit\" to activate")
sleep(1)

/// Whether keys really go through Seamtype: TISSelectInputSource can report success while the
/// menu bar (and the keys) stay on the previous source, so type a word and look.
func typingThroughSeamtype() -> Bool {
    appleScript("tell application \"TextEdit\" to set text of front document to \"\"")
    usleep(300_000)
    for ch in "dkssud " { press(ch) }
    usleep(500_000)
    let text = appleScript("tell application \"TextEdit\" to get text of front document")
    appleScript("tell application \"TextEdit\" to set text of front document to \"\"")
    return text == "안녕 "
}

TISSelectInputSource(seamtype)
usleep(500_000)
if !typingThroughSeamtype() {
    // Picking it in the input menu, as a person would, does take.
    appleScript("""
        tell application "System Events" to tell process "TextInputMenuAgent"
            click menu bar item 1 of menu bar 2
            delay 0.5
            click menu item "Seamtype" of menu 1 of menu bar item 1 of menu bar 2
        end tell
        """)
    sleep(1)
    guard typingThroughSeamtype() else {
        appleScript("tell application \"TextEdit\" to close front document saving no")
        TISSelectInputSource(previousSource)
        fatalError("couldn't switch TextEdit to Seamtype (dkssud didn't become 안녕)")
    }
}
var passed = 0
for c in cases where c.count == 2 {
    let (script, expected) = (c[0], c[1].replacingOccurrences(of: "␣", with: " "))
    appleScript("tell application \"TextEdit\" to set text of front document to \"\"")
    usleep(300_000)
    for ch in script { press(ch) }
    usleep(500_000)
    let actual = appleScript("tell application \"TextEdit\" to get text of front document") ?? "<nil>"
    let ok = actual == expected
    if ok { passed += 1 }
    print("\(ok ? "PASS" : "FAIL")  \(script)  →  \(actual)\(ok ? "" : "   (expected \(expected))")")
    // Commit anything left composing before the next case.
    press("⏎")
}
appleScript("tell application \"TextEdit\" to close front document saving no")
TISSelectInputSource(previousSource)
let total = cases.filter { $0.count == 2 }.count
print("\(passed)/\(total) passed")
exit(passed == total ? 0 : 1)
