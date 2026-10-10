// Types the README's examples into a TextEdit window through the installed Seamtype, at a
// readable pace, while screencapture records that window.
//
// usage: demo <output.mov>
// script: characters as typed; ⏎ Return, ⎋ Esc, ⌫ Delete; ‖ pauses so the preview can be read.
import AppKit
import Carbon

let lines = [
    "dkssudgktpdy, hello world!⏎",
    "dlrjs githubdp commitgkf rjdi.⏎",
    "kyouhagoogledekensaku‖ ‖⏎",
]

/// Window, in points from the top left of the main screen.
/// Tall enough below the last line for the kanji candidate window.
let frame = (x: 120, y: 160, w: 700, h: 400)

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
    m[" "] = (49, false); m[","] = (43, false); m["."] = (47, false); m["?"] = (44, true); m["!"] = (18, true)
    m["⏎"] = (36, false); m["⎋"] = (53, false); m["⌫"] = (51, false)
    return m
}()

/// Seconds after each key: a little longer around word ends, so each decision can be seen.
func delay(after ch: Character) -> Double {
    switch ch {
    case "‖": return 0.9
    case "⏎": return 0.7
    case " ", ",", ".", "!", "?": return 0.35
    default: return 0.11
    }
}

func post(_ code: CGKeyCode, _ flags: CGEventFlags) {
    let source = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)!
        e.flags = flags
        e.post(tap: .cghidEventTap)
        usleep(12_000)
    }
}

func press(_ ch: Character) {
    if ch != "‖" {
        guard let (code, shift) = keyCodes[ch] else { fatalError("no key for \(ch)") }
        post(code, shift ? .maskShift : [])
    }
    usleep(UInt32(delay(after: ch) * 1_000_000))
}

@discardableResult
func appleScript(_ source: String) -> String? {
    var error: NSDictionary?
    let result = NSAppleScript(source: source)!.executeAndReturnError(&error)
    if let error { FileHandle.standardError.write("AppleScript: \(error)\n".data(using: .utf8)!) }
    return result.stringValue
}

func sourceID(_ s: TISInputSource) -> String {
    guard let p = TISGetInputSourceProperty(s, kTISPropertyInputSourceID) else { return "" }
    return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
}
let previousSource = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
let sources = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
guard let seamtype = sources.first(where: { sourceID($0) == "com.aimdevlee.inputmethod.Seamtype" }) else {
    print("Seamtype isn't an enabled input source"); exit(1)
}

// A fresh document in a large font: type one character, size it, select it, and the typing
// replaces it with the same attributes.
appleScript("""
tell application "TextEdit"
    activate
    make new document
    set bounds of front window to {\(frame.x), \(frame.y), \(frame.x + frame.w), \(frame.y + frame.h)}
    set text of front document to " "
    set font of text of front document to "Helvetica Neue"
    set size of text of front document to 32
end tell
""")
sleep(1)
TISSelectInputSource(seamtype)
usleep(500_000)
post(0, .maskCommand)  // ⌘A
usleep(300_000)

// Record for as long as the typing takes, plus a moment at each end.
let typing = lines.joined().reduce(0) { $0 + delay(after: $1) + 0.024 }
let output = CommandLine.arguments[1]
let recorder = Process()
recorder.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
recorder.arguments = ["-v", "-x", "-V\(Int(typing.rounded(.up)) + 6)", "-R\(frame.x),\(frame.y),\(frame.w),\(frame.h)", output]
try! recorder.run()
sleep(3)  // screencapture takes a moment to start: begin on the empty document

for ch in lines.joined() { press(ch) }

recorder.waitUntilExit()
TISSelectInputSource(previousSource)
let text = appleScript("tell application \"TextEdit\" to get text of front document") ?? ""
appleScript("tell application \"TextEdit\" to close front document saving no")
print(text)
