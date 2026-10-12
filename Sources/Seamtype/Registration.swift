import AppKit
import Carbon

/// `Seamtype --register`, run from the freshly installed copy by every install path (the pkg's
/// postinstall, get.sh, install.sh), after the old process has been stopped.
@MainActor
enum Registration {
    /// Registers this bundle as an input method and enables its input source; returns the status.
    static func run() -> OSStatus {
        forgetOtherCopies()
        let status = TISRegisterInputSource(Bundle.main.bundleURL as CFURL)
        let filter = [kTISPropertyInputSourceID as String: SeamtypeSource.id] as CFDictionary
        if status == noErr, let source = (TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource])?.first {
            TISEnableInputSource(source)
        }
        reconnect()
        return status
    }

    /// Any other copy LaunchServices knows (a build folder, a stale download, an old path) can be
    /// the one macOS launches as the input method, and then nothing types until a restart.
    private static func forgetOtherCopies() {
        let ours = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        for url in NSWorkspace.shared.urlsForApplications(withBundleIdentifier: SeamtypeSource.id)
        where url.resolvingSymlinksInPath().standardizedFileURL != ours {
            Uninstaller.launch(lsregister, ["-u", url.path])
        }
        Uninstaller.launch(lsregister, ["-f", ours.path])
    }

    /// Apps that were typing through the process the install stopped keep a dead connection until
    /// the input source changes; switching away and back makes macOS launch the new copy for them.
    private static func reconnect() {
        guard SeamtypeSource.isCurrent, let other = Uninstaller.fallbackSource() else { return }
        TISSelectInputSource(other)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
        SeamtypeSource.select()
    }
}
