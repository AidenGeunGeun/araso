// Tells the running Legato that its files changed, as the settings window does, so it reads its
// settings again; with "kanjiReset" it also drops its kanji learning and reads it from disk.
//
// usage: notify [kanjiReset]
import Foundation
let reset = CommandLine.arguments.dropFirst().first == "kanjiReset"
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.nyttastudio.inputmethod.Legato.settingsChanged"),
    object: reset ? "kanjiReset" : nil, userInfo: nil, deliverImmediately: true)
