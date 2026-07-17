import Cocoa
import QuartzCore

/// A hover-revealed status capsule that visually grows from the physical camera cutout. At rest the
/// black shape matches the notch exactly; active work is communicated by a restrained lower-edge
/// breath, and the icon/status appear only after the pointer reveals the control.
final class NotchHUDController: NSObject {
    enum Activity { case idle, active, permission }

    private let panel: NSPanel
    private let hudView: NotchHUDView
    private let onClick: (NSEvent, NSView) -> Void
    private var currentText = ""
    private var currentActivity: Activity = .idle
    private var isPresented = false
    private var isHovered = false

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
        hudView.onHoverChanged = { [weak self] hovering in
            guard let self, hovering != self.isHovered else { return }
            self.isHovered = hovering
            self.layoutPanel(animated: true)
        }
        panel.contentView = hudView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false // the shape layer owns a contour shadow; never shadow the window rectangle
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilityDisplayChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func show(animated: Bool) {
        isPresented = true
        isHovered = false
        layoutPanel(animated: false)
        if animated && !reduceMotion {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
    }

    func hide(animated: Bool) {
        isPresented = false
        isHovered = false
        hudView.stopPulse()
        guard animated && !reduceMotion else { panel.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            panel?.orderOut(nil)
            panel?.alphaValue = 1
        })
    }

    func update(image: NSImage?, text: String, activity: Activity, animated: Bool = true) {
        let textChanged = text != currentText
        currentText = text
        currentActivity = activity
        hudView.update(image: image, text: text, activity: activity, reduceMotion: reduceMotion)
        // Collapsed geometry is deliberately stable; status changes alter only the subtle breath.
        if isPresented && isHovered && textChanged { layoutPanel(animated: animated) }
    }

    @objc private func screenGeometryChanged() {
        if isPresented { layoutPanel(animated: true) }
    }

    @objc private func accessibilityDisplayChanged() {
        hudView.update(image: nil, text: currentText, activity: currentActivity, reduceMotion: reduceMotion)
        if isPresented { layoutPanel(animated: false) }
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private func targetScreen() -> NSScreen? {
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
        let bodyHeight = hasNotch ? screen.safeAreaInsets.top : 24
        let hitSlop: CGFloat = 10

        let font = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .medium)
        let textWidth = currentText.isEmpty ? 0 : ceil(
            (currentText as NSString).size(withAttributes: [.font: font]).width
        )
        let expandedWidth = min(440, max(baseWidth + 34, textWidth + 180))
        let targetWidth = isHovered ? expandedWidth : baseWidth + hitSlop * 2
        let targetHeight = isHovered ? bodyHeight + 34 : bodyHeight + hitSlop
        let target = NSRect(
            x: round(screen.frame.midX - targetWidth / 2),
            y: screen.frame.maxY - targetHeight,
            width: targetWidth,
            height: targetHeight
        )

        hudView.configure(
            hasPhysicalNotch: hasNotch,
            notchWidth: baseWidth,
            bodyHeight: bodyHeight,
            hitSlop: hitSlop,
            expanded: isHovered,
            reduceMotion: reduceMotion
        )

        let shouldAnimate = animated && panel.isVisible && !reduceMotion
        if shouldAnimate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = isHovered ? 0.24 : 0.20
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
    var onHoverChanged: ((Bool) -> Void)?

    private let shapeLayer = CAShapeLayer()
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var tracking: NSTrackingArea?
    private var hasPhysicalNotch = true
    private var physicalNotchWidth: CGFloat = 220
    private var bodyHeight: CGFloat = 38
    private var hitSlop: CGFloat = 10
    private var expanded = false
    private var reduceMotion = false
    private var activity: NotchHUDController.Activity = .idle
    private var pulseIsRunning = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(shapeLayer)
        shapeLayer.fillColor = NSColor.black.cgColor
        shapeLayer.shadowOffset = CGSize(width: 0, height: -1)
        shapeLayer.shadowRadius = 6

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.animates = true
        iconView.alphaValue = 0
        addSubview(iconView)

        label.font = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .medium)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.alphaValue = 0
        addSubview(label)

        setAccessibilityRole(.button)
        setAccessibilityLabel("Codex Status Bar")
        setAccessibilityHelp("Shows the current Codex status. Press to open tasks and MCP servers.")
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func configure(hasPhysicalNotch: Bool, notchWidth: CGFloat, bodyHeight: CGFloat,
                   hitSlop: CGFloat, expanded: Bool, reduceMotion: Bool) {
        self.hasPhysicalNotch = hasPhysicalNotch
        physicalNotchWidth = notchWidth
        self.bodyHeight = bodyHeight
        self.hitSlop = hitSlop
        self.expanded = expanded
        self.reduceMotion = reduceMotion
        updateContentVisibility(animated: window?.isVisible == true)
        needsLayout = true
    }

    func update(image: NSImage?, text: String, activity: NotchHUDController.Activity, reduceMotion: Bool) {
        if let image { iconView.image = image }
        label.stringValue = text
        if self.activity != activity { stopPulse() }
        self.activity = activity
        self.reduceMotion = reduceMotion
        updateAccent()
        syncPulse()
        needsLayout = true
    }

    func stopPulse() {
        pulseIsRunning = false
        shapeLayer.removeAnimation(forKey: "notchBreath")
        shapeLayer.removeAnimation(forKey: "notchGlow")
    }

    override func layout() {
        super.layout()
        shapeLayer.frame = bounds
        updateShape()

        let visibleBandHeight: CGFloat = expanded ? 34 : 0
        let band = NSRect(x: 0, y: 0, width: bounds.width, height: visibleBandHeight)
        let iconSize: CGFloat = 22
        let gap: CGFloat = label.stringValue.isEmpty ? 0 : 7
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
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }
    override func mouseDown(with event: NSEvent) { onClick?(event, self) }

    private func updateContentVisibility(animated: Bool) {
        let alpha: CGFloat = expanded ? 1 : 0
        guard animated && !reduceMotion else {
            iconView.alphaValue = alpha
            label.alphaValue = alpha
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = expanded ? 0.16 : 0.10
            iconView.animator().alphaValue = alpha
            label.animator().alphaValue = alpha
        }
    }

    private func updateAccent() {
        let accent: NSColor
        switch activity {
        case .permission: accent = NSColor(srgbRed: 0.95, green: 0.73, blue: 0.18, alpha: 1)
        case .active: accent = NSColor(srgbRed: 0.42, green: 0.51, blue: 1, alpha: 1)
        case .idle: accent = .clear
        }
        shapeLayer.shadowColor = accent.cgColor
        shapeLayer.shadowOpacity = activity == .idle ? 0 : (reduceMotion ? 0.15 : 0.12)
    }

    private func updateShape() {
        let path: CGPath
        if expanded {
            path = bottomRoundedPath(in: bounds, radius: hasPhysicalNotch ? 16 : 17)
        } else {
            path = collapsedPath(extension: activity == .idle ? 0 : (reduceMotion ? 3 : 2))
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeLayer.path = path
        shapeLayer.shadowPath = path
        CATransaction.commit()
        syncPulse()
    }

    private func syncPulse() {
        let shouldPulse = !expanded && activity != .idle && !reduceMotion && bounds.width > 0
        if !shouldPulse {
            stopPulse()
            if bounds.width > 0 { updateStaticShape() }
            return
        }
        guard !pulseIsRunning else { return }
        pulseIsRunning = true

        let pathAnimation = CABasicAnimation(keyPath: "path")
        pathAnimation.fromValue = collapsedPath(extension: 2)
        pathAnimation.toValue = collapsedPath(extension: 6)
        pathAnimation.duration = activity == .permission ? 1.05 : 1.35
        pathAnimation.autoreverses = true
        pathAnimation.repeatCount = .infinity
        pathAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        shapeLayer.add(pathAnimation, forKey: "notchBreath")

        let glow = CABasicAnimation(keyPath: "shadowOpacity")
        glow.fromValue = activity == .permission ? 0.16 : 0.08
        glow.toValue = activity == .permission ? 0.32 : 0.20
        glow.duration = pathAnimation.duration
        glow.autoreverses = true
        glow.repeatCount = .infinity
        glow.timingFunction = pathAnimation.timingFunction
        shapeLayer.add(glow, forKey: "notchGlow")
    }

    private func updateStaticShape() {
        let path = expanded
            ? bottomRoundedPath(in: bounds, radius: hasPhysicalNotch ? 16 : 17)
            : collapsedPath(extension: activity == .idle ? 0 : (reduceMotion ? 3 : 2))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeLayer.path = path
        shapeLayer.shadowPath = path
        CATransaction.commit()
    }

    private func collapsedPath(extension amount: CGFloat) -> CGPath {
        let width = min(physicalNotchWidth, bounds.width)
        let x = round(bounds.midX - width / 2)
        let rect = NSRect(
            x: x,
            y: max(0, bounds.height - bodyHeight - amount),
            width: width,
            height: bodyHeight + amount
        )
        return bottomRoundedPath(in: rect, radius: hasPhysicalNotch ? 12 : 14)
    }

    private func bottomRoundedPath(in rect: NSRect, radius: CGFloat) -> CGPath {
        let r = min(radius, rect.width / 2, rect.height / 2)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.minY),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + r),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
