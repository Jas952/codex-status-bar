import Cocoa
import QuartzCore

/// A non-activating panel that grows out of the physical camera cutout. The camera pixels are not
/// drawable, so the icon and label live in the visible band immediately below it.
final class NotchHUDController: NSObject {
    enum Activity { case idle, active, permission }

    private let panel: NSPanel
    private let hudView: NotchHUDView
    private let onClick: (NSEvent, NSView) -> Void
    private var currentText = ""
    private var currentActivity: Activity = .idle
    private var isPresented = false

    init(onClick: @escaping (NSEvent, NSView) -> Void) {
        self.onClick = onClick
        hudView = NotchHUDView(frame: .zero)
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        hudView.onClick = { [weak self] event, view in self?.onClick(event, view) }
        panel.contentView = hudView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenGeometryChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func show(animated: Bool) {
        isPresented = true
        layoutPanel(animated: false)
        if animated {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
    }

    func hide(animated: Bool) {
        isPresented = false
        guard animated else { panel.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            panel?.orderOut(nil)
            panel?.alphaValue = 1
        })
    }

    func update(image: NSImage?, text: String, activity: Activity, animated: Bool = true) {
        let geometryChanged = text != currentText || activity != currentActivity
        currentText = text
        currentActivity = activity
        hudView.update(image: image, text: text, activity: activity)
        if isPresented { layoutPanel(animated: animated && geometryChanged) }
    }

    @objc private func screenGeometryChanged() {
        if isPresented { layoutPanel(animated: true) }
    }

    private func targetScreen() -> NSScreen? {
        // Prefer a real camera cutout even when another display currently owns the menu bar.
        NSScreen.screens.first(where: { notchWidth(on: $0) > 0 }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func notchWidth(on screen: NSScreen) -> CGFloat {
        guard let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return 0 }
        return max(0, right.minX - left.maxX)
    }

    private func layoutPanel(animated: Bool) {
        guard let screen = targetScreen() else { return }
        let physicalNotchWidth = notchWidth(on: screen)
        let hasNotch = physicalNotchWidth > 0 && screen.safeAreaInsets.top > 0
        let baseWidth = hasNotch ? physicalNotchWidth : 176
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .medium)
        let textWidth = currentText.isEmpty ? 0 : ceil((currentText as NSString).size(withAttributes: [.font: font]).width)
        // Keep enough breathing room for the icon, gap, and 14pt side insets. The extra reserve also
        // prevents the final timer digit from collapsing into an ellipsis at the physical notch width.
        let desiredWidth = min(440, max(baseWidth, textWidth + 180))
        let visibleBand: CGFloat = currentActivity == .idle ? 24 : 34
        let topInset = hasNotch ? screen.safeAreaInsets.top : 8
        let desiredHeight = topInset + visibleBand
        let target = NSRect(
            x: round(screen.frame.midX - desiredWidth / 2),
            y: screen.frame.maxY - desiredHeight,
            width: desiredWidth,
            height: desiredHeight
        )

        hudView.configureForNotch(hasNotch, visibleBandHeight: visibleBand)
        if animated, panel.isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = currentActivity == .idle ? 0.28 : 0.36
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
        }
    }
}

private final class NotchHUDView: NSView {
    var onClick: ((NSEvent, NSView) -> Void)?

    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var tracking: NSTrackingArea?
    private var visibleBandHeight: CGFloat = 24
    private var hasPhysicalNotch = true
    private var activity: NotchHUDController.Activity = .idle

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.borderWidth = 0.75
        layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        layer?.cornerCurve = .continuous

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.animates = true
        addSubview(iconView)

        label.font = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .medium)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        addSubview(label)
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func configureForNotch(_ hasNotch: Bool, visibleBandHeight: CGFloat) {
        hasPhysicalNotch = hasNotch
        self.visibleBandHeight = visibleBandHeight
        layer?.cornerRadius = hasNotch ? 15 : 17
        layer?.maskedCorners = hasNotch
            ? [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            : [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        needsLayout = true
    }

    func update(image: NSImage?, text: String, activity: NotchHUDController.Activity) {
        iconView.image = image
        label.stringValue = text
        self.activity = activity
        let accent: NSColor
        switch activity {
        case .permission: accent = NSColor(srgbRed: 0.95, green: 0.73, blue: 0.18, alpha: 1)
        case .active: accent = NSColor(srgbRed: 0.42, green: 0.51, blue: 1, alpha: 1)
        case .idle: accent = .white
        }
        layer?.borderColor = accent.withAlphaComponent(activity == .idle ? 0.10 : 0.24).cgColor
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let band = NSRect(x: 0, y: 0, width: bounds.width, height: visibleBandHeight)
        let iconSize: CGFloat = activity == .idle ? 20 : 22
        let gap: CGFloat = label.stringValue.isEmpty ? 0 : 7
        // A truncating NSTextField reports an intrinsic width based on its previous constrained
        // frame, which made the label progressively collapse even while the panel expanded. Measure
        // the string independently and give AppKit a small glyph-bearing reserve instead.
        let available = bounds.width - iconSize - gap - 28
        let natural = label.stringValue.isEmpty ? 0 : ceil(
            (label.stringValue as NSString).size(withAttributes: [.font: label.font as Any]).width
        ) + 28
        let measured = min(available, natural)
        let total = iconSize + gap + measured
        let startX = round(band.midX - total / 2)
        iconView.frame = NSRect(x: startX, y: round(band.midY - iconSize / 2), width: iconSize, height: iconSize)
        label.frame = NSRect(
            x: iconView.frame.maxX + gap,
            y: round(band.midY - 9),
            width: measured,
            height: 18
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().alphaValue = 0.86
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            animator().alphaValue = 1
        }
    }

    override func mouseDown(with event: NSEvent) { onClick?(event, self) }
}
