import Cocoa

/// Seamtype's icon shown for a moment under the caret when it pauses (struck through) or
/// resumes in a text field. The menu bar icon can't show it (the bundle is signed, so the icon
/// is fixed). Menu bar size, like the system's input source indicator; the struck-through icon
/// is drawn at build time (scripts/make-icon.swift --slash).
@MainActor enum PauseHUD {
    private static var panel: NSPanel?
    private static var imageView: NSImageView?
    /// Bumped on every show, so an older fade-out leaves a newer icon alone.
    private static var shown = 0

    private static let icons: (on: NSImage, paused: NSImage)? = {
        func load(_ name: String) -> NSImage? {
            let image = Bundle.main.url(forResource: name, withExtension: "tiff").flatMap(NSImage.init(contentsOf:))
            image?.isTemplate = true
            return image
        }
        guard let on = load("Seamtype"), let paused = load("SeamtypePaused") else { return nil }
        return (on, paused)
    }()

    /// `caret` is the caret's line in screen coordinates, or `.zero` when the app doesn't say.
    static func show(paused: Bool, caret: NSRect) {
        guard let icons else { return } // not built into an app bundle (development)
        let (panel, imageView) = make()
        let image = paused ? icons.paused : icons.on
        imageView.image = image
        imageView.setAccessibilityLabel(paused ? L("Seamtype paused") : L("Seamtype resumed"))
        let size = NSSize(width: image.size.width + 14, height: image.size.height + 8)
        panel.setFrame(NSRect(origin: origin(for: size, caret: caret), size: size), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        shown += 1
        let current = shown
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard current == shown else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel.animator().alphaValue = 0 }) {
                MainActor.assumeIsolated { if current == shown { panel.orderOut(nil) } }
            }
        }
    }

    /// Just under the caret's line (above it near the bottom of the screen), kept on screen.
    /// Without a caret, near the top of the screen the mouse is on.
    private static func origin(for size: NSSize, caret: NSRect) -> NSPoint {
        let gap: CGFloat = 4
        let anchor = caret == .zero ? NSEvent.mouseLocation : caret.origin
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return anchor }
        var point: NSPoint
        if caret == .zero {
            point = NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 40)
        } else {
            point = NSPoint(x: caret.minX, y: caret.minY - size.height - gap)
            if point.y < visible.minY { point.y = caret.maxY + gap }
        }
        point.x = min(max(point.x, visible.minX), visible.maxX - size.width)
        point.y = min(max(point.y, visible.minY), visible.maxY - size.height)
        return point
    }

    private static func make() -> (NSPanel, NSImageView) {
        if let panel, let imageView { return (panel, imageView) }
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 6
        background.layer?.masksToBounds = true

        let imageView = NSImageView()
        imageView.contentTintColor = .labelColor
        imageView.imageScaling = .scaleNone
        imageView.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: background.centerYAnchor),
        ])
        panel.contentView = background
        self.panel = panel
        self.imageView = imageView
        return (panel, imageView)
    }
}
