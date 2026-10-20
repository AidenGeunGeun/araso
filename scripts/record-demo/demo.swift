// Types the README's examples into page.html in a Safari window through the installed Araso,
// at a readable pace, while screencapture records the whole screen (the input menu in the menu
// bar stays Araso's throughout: the film shows it).
//
// usage: demo <directory> <page URL>
//   writes demo.mov and keys.json: the page's and the input menu's frames on screen, in points
//   from the top left, and each key with its time in seconds since the recording was started
// script: characters as typed; ⏎ Return, ⎋ Esc, ⌫ Delete; ‖ pauses so the preview can be read.
import AppKit
import Carbon

let lines = [
    "Stay hungry, stay foolishsms wkqtmdml akfdlek.⏎",
    "wagahaihanekodearu‖ ‖sms thtpzldml thtjfdlek.⏎",
    "Hello, worldhasaishonopuroguramudesu‖ ‖.⏎",
]

/// Window, in points from the top left of the main screen.
/// Tall enough below the last line for the kanji candidate window.
let frame = (x: 120, y: 120, w: 960, h: 600)

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

/// Seconds the switch to Araso takes, at the start of the recording.
let switching = 6.0

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
guard let araso = sources.first(where: { sourceID($0) == "com.nyttastudio.inputmethod.Araso" }) else {
    print("Araso isn't an enabled input source"); exit(1)
}

/// The first element under `element` (depth first) with this accessibility role.
func find(_ role: String, in element: AXUIElement) -> AXUIElement? {
    var value: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success,
       value as? String == role { return element }
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
          let children = value as? [AXUIElement] else { return nil }
    for child in children { if let found = find(role, in: child) { return found } }
    return nil
}

func rect(of element: AXUIElement) -> CGRect {
    var value: CFTypeRef?
    var origin = CGPoint.zero, size = CGSize.zero
    AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value)
    AXValueGetValue(value as! AXValue, .cgPoint, &origin)
    AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value)
    AXValueGetValue(value as! AXValue, .cgSize, &size)
    return CGRect(origin: origin, size: size)
}

func click(_ point: CGPoint) {
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)!
            .post(tap: .cghidEventTap)
        usleep(30_000)
    }
}

// A new Safari window on the page, then a click in its text area (and the pointer moved off it).
let page = CommandLine.arguments[2]
appleScript("""
tell application "Safari"
    activate
    make new document with properties {URL:"\(page)"}
    set bounds of front window to {\(frame.x), \(frame.y), \(frame.x + frame.w), \(frame.y + frame.h)}
end tell
""")
sleep(2)
guard let safari = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first else {
    print("Safari isn't running"); exit(1)
}
var window: CFTypeRef?
AXUIElementCopyAttributeValue(AXUIElementCreateApplication(safari.processIdentifier), kAXFocusedWindowAttribute as CFString, &window)
guard let window, let webArea = find("AXWebArea", in: window as! AXUIElement) else {
    print("no Safari page found (does the terminal have Accessibility permission?)"); exit(1)
}
let content = rect(of: webArea)
click(CGPoint(x: content.midX, y: content.midY))
// The film opens on ABC, switched to Araso once from the input menu.
guard let abc = sources.first(where: { sourceID($0) == "com.apple.keylayout.ABC" }) else {
    print("ABC isn't an enabled input source"); exit(1)
}
TISSelectInputSource(abc)
usleep(500_000)

// Record for as long as the typing takes, plus a moment at each end.
let typing = lines.joined().reduce(0) { $0 + delay(after: $1) + 0.024 } + switching
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let recorder = Process()
recorder.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
recorder.arguments = ["-v", "-x", "-C", "-V\(Int(typing.rounded(.up)) + 6)", directory.appendingPathComponent("demo.mov").path]
try! recorder.run()
let started = Date()
sleep(3)  // screencapture takes a moment to start: begin on the empty document

/// The input menu's item in the menu bar, and Araso's item in its open menu.
func inputMenuItem() -> AXUIElement? {
    guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextInputMenuAgent").first
    else { return nil }
    var bar: CFTypeRef?, items: CFTypeRef?
    AXUIElementCopyAttributeValue(AXUIElementCreateApplication(agent.processIdentifier), kAXExtrasMenuBarAttribute as CFString, &bar)
    guard let bar else { return nil }
    AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &items)
    return (items as? [AXUIElement])?.first
}

func arasoMenuItem(in menu: AXUIElement) -> AXUIElement? {
    var title: CFTypeRef?
    AXUIElementCopyAttributeValue(menu, kAXTitleAttribute as CFString, &title)
    if title as? String == "Araso" { return menu }
    var children: CFTypeRef?
    AXUIElementCopyAttributeValue(menu, kAXChildrenAttribute as CFString, &children)
    for child in (children as? [AXUIElement]) ?? [] { if let found = arasoMenuItem(in: child) { return found } }
    return nil
}

/// The pointer glides to `point`, as a hand would move it.
func glide(to point: CGPoint, seconds: Double = 0.6) {
    let from = CGEvent(source: nil)!.location
    let steps = Int(seconds * 60)
    for i in 1...steps {
        let x = Double(i) / Double(steps), e = x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
        let p = CGPoint(x: from.x + (point.x - from.x) * e, y: from.y + (point.y - from.y) * e)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)!
            .post(tap: .cghidEventTap)
        usleep(UInt32(1_000_000 / 60))
    }
}

// Open the input menu, choose Araso, and back to the page. The pointer then waits outside it.
if let menu = inputMenuItem() {
    let icon = rect(of: menu)
    glide(to: CGPoint(x: icon.midX, y: icon.midY), seconds: 0.9)
    usleep(250_000)
    click(CGPoint(x: icon.midX, y: icon.midY))
    usleep(900_000)
    if let item = arasoMenuItem(in: menu) {
        let r = rect(of: item)
        glide(to: CGPoint(x: r.minX + 60, y: r.midY), seconds: 0.5)
        usleep(450_000)
        click(CGPoint(x: r.minX + 60, y: r.midY))
    } else {
        post(53, [])  // Esc closes the menu
    }
    usleep(500_000)
}
TISSelectInputSource(araso)
glide(to: CGPoint(x: content.minX + 380, y: content.minY + 120), seconds: 0.8)
click(CGPoint(x: content.minX + 380, y: content.minY + 120))
usleep(200_000)
glide(to: CGPoint(x: content.maxX + 60, y: content.midY), seconds: 0.5)
usleep(400_000)

/// The process whose window is frontmost, the one that gets the keys.
func frontPID() -> pid_t? {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
    return windows?.first { $0[kCGWindowLayer as String] as? Int == 0 }?[kCGWindowOwnerPID as String] as? pid_t
}

// Every key goes to Safari or none does: if another app takes focus, stop rather than type into it.
var keys: [[String: Any]] = []
for ch in lines.joined() {
    guard frontPID() == safari.processIdentifier else {
        recorder.terminate()
        TISSelectInputSource(previousSource)
        print("Safari lost focus: stopped (record again, without touching the keyboard or pointer)")
        exit(1)
    }
    if ch != "‖" { keys.append(["t": Date().timeIntervalSince(started), "k": String(ch)]) }
    press(ch)
}

recorder.waitUntilExit()

// The input menu in the menu bar (Araso's icon), if it's shown.
var inputMenu: [String: Double] = [:]
for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextInputMenuAgent") {
    var bar: CFTypeRef?, items: CFTypeRef?
    AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier), kAXExtrasMenuBarAttribute as CFString, &bar)
    guard let bar else { continue }
    AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &items)
    if let item = (items as? [AXUIElement])?.first {
        let r = rect(of: item)
        inputMenu = ["x": r.minX, "y": r.minY, "w": r.width, "h": r.height]
    }
}
let screen = NSScreen.main!.frame.size
let log: [String: Any] = [
    "screen": ["w": screen.width, "h": screen.height],
    "inputMenu": inputMenu,
    "page": ["x": content.minX, "y": content.minY, "w": content.width, "h": content.height],
    "keys": keys,
]
try! JSONSerialization.data(withJSONObject: log, options: [.prettyPrinted, .sortedKeys])
    .write(to: directory.appendingPathComponent("keys.json"))
TISSelectInputSource(previousSource)
var text: CFTypeRef?
if let area = find("AXTextArea", in: webArea) {
    AXUIElementCopyAttributeValue(area, kAXValueAttribute as CFString, &text)
}
appleScript("tell application \"Safari\" to close front window")
print(text as? String ?? "")
