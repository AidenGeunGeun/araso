import AppKit
import Carbon

/// `Seamtype --register`, run from the freshly installed copy by every install path (the pkg's
/// postinstall, get.sh, install.sh), after the old process has been stopped.
@MainActor
enum Registration {
    /// Registers this bundle as an input method and enables its input source; returns the status.
    static func run() -> OSStatus {
        forgetOtherCopies()
        let filter = [kTISPropertyInputSourceID as String: SeamtypeSource.id] as CFDictionary
        func listed() -> TISInputSource? {
            (TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource])?.first
        }
        // Registering one macOS already lists (a reinstall at the same path) is left out, as
        // Squirrel and vChewing do; so is enabling one the user has already added.
        var status = noErr
        if listed() == nil { status = TISRegisterInputSource(Bundle.main.bundleURL as CFURL) }
        if status == noErr, let source = listed(),
           TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled)
               .map({ CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque($0).takeUnretainedValue()) }) != true {
            TISEnableInputSource(source)
        }
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
}
