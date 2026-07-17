import Cocoa
import QuartzCore

/// A hover-revealed status surface that grows from the physical camera cutout. The window itself
/// never animates frame-by-frame: Core Animation morphs the notch silhouette and its lower contour.
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
        hudView.onHoverChanged = { [weak self] hovering in self?.setHovered(hovering) }
        panel.contentView = hudView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
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
        layoutPanel(expanded: false)
        hudView.setExpanded(false, animated: false)
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
        hudView.stopMotion()
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
        currentText = text
        currentActivity = activity
        hudView.update(image: image, text: text, activity: activity, reduceMotion: reduceMotion)
    }

    private func setHovered(_ hovering: Bool) {
        guard hovering != isHovered, isPresented else { return }
        isHovered = hovering
        if hovering {
            // Stop animations expressed in the narrow window's coordinates before widening it.
            hudView.prepareForWindowResize()
            layoutPanel(expanded: true)
            hudView.setExpanded(true, animated: true)
        } else {
            hudView.setExpanded(false, animated: true) { [weak self] in
                guard let self, !self.isHovered, self.isPresented else { return }
                self.layoutPanel(expanded: false)
            }
        }
    }

    @objc private func screenGeometryChanged() {
        guard isPresented else { return }
        layoutPanel(expanded: isHovered)
        hudView.setExpanded(isHovered, animated: false)
    }

    @objc private func accessibilityDisplayChanged() {
        hudView.update(image: nil, text: currentText, activity: currentActivity, reduceMotion: reduceMotion)
        guard isPresented else { return }
        layoutPanel(expanded: isHovered)
        hudView.setExpanded(isHovered, animated: false)
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

    private func layoutPanel(expanded: Bool) {
        guard let screen = targetScreen() else { return }
        let physicalNotchWidth = notchWidth(on: screen)
        let hasNotch = physicalNotchWidth > 0 && screen.safeAreaInsets.top > 0
        let baseWidth = hasNotch ? physicalNotchWidth : 176
        let bodyHeight = hasNotch ? screen.safeAreaInsets.top : 24
        let hitSlop: CGFloat = 12
        let targetWidth = expanded ? min(360, baseWidth + 120) : baseWidth + hitSlop * 2
        let targetHeight = expanded ? bodyHeight + 28 : bodyHeight + hitSlop
        let target = NSRect(
            x: round(screen.frame.midX - targetWidth / 2),
            y: screen.frame.maxY - targetHeight,
            width: targetWidth,
            height: targetHeight
        )

        // NSWindow frame animation was the source of visible stalls when the timer refreshed.
        panel.setFrame(target, display: true)
        hudView.configure(
            hasPhysicalNotch: hasNotch,
            notchWidth: baseWidth,
            bodyHeight: bodyHeight,
            hitSlop: hitSlop,
            reduceMotion: reduceMotion
        )
        hudView.layoutSubtreeIfNeeded()
    }
}

private final class NotchHUDView: NSView {
    var onClick: ((NSEvent, NSView) -> Void)?
    var onHoverChanged: ((Bool) -> Void)?

    private let shapeLayer = CAShapeLayer()
    private let auraLayer = CAShapeLayer()
    private let shimmerLayer = CAGradientLayer()
    private let shimmerMask = CAShapeLayer()
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var tracking: NSTrackingArea?
    private var hasPhysicalNotch = true
    private var physicalNotchWidth: CGFloat = 220
    private var bodyHeight: CGFloat = 38
    private var hitSlop: CGFloat = 12
    private var expanded = false
    private var reduceMotion = false
    private var activity: NotchHUDController.Activity = .idle
    private var pulseIsRunning = false
    private var transitionGeneration = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        shapeLayer.fillColor = NSColor.black.cgColor
        layer?.addSublayer(shapeLayer)

        auraLayer.fillColor = NSColor.clear.cgColor
        auraLayer.lineCap = .round
        auraLayer.lineWidth = 1.4
        auraLayer.shadowOffset = .zero
        auraLayer.shadowRadius = 7
        layer?.addSublayer(auraLayer)

        shimmerLayer.startPoint = CGPoint(x: 0, y: 0.5)
        shimmerLayer.endPoint = CGPoint(x: 1, y: 0.5)
        shimmerLayer.mask = shimmerMask
        shimmerMask.fillColor = NSColor.clear.cgColor
        shimmerMask.strokeColor = NSColor.white.cgColor
        shimmerMask.lineCap = .round
        shimmerMask.lineWidth = 1.25
        layer?.addSublayer(shimmerLayer)

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
                   hitSlop: CGFloat, reduceMotion: Bool) {
        self.hasPhysicalNotch = hasPhysicalNotch
        physicalNotchWidth = notchWidth
        self.bodyHeight = bodyHeight
        self.hitSlop = hitSlop
        self.reduceMotion = reduceMotion
        needsLayout = true
    }

    func update(image: NSImage?, text: String, activity: NotchHUDController.Activity, reduceMotion: Bool) {
        if let image { iconView.image = image }
        label.stringValue = text
        let stateChanged = self.activity != activity || self.reduceMotion != reduceMotion
        self.activity = activity
        self.reduceMotion = reduceMotion
        updateAccent()
        if stateChanged { stopMotion() }
        syncMotion()
        needsLayout = true
    }

    func setExpanded(_ value: Bool, animated: Bool, completion: (() -> Void)? = nil) {
        transitionGeneration += 1
        let generation = transitionGeneration
        let fromShape = shapeLayer.presentation()?.path ?? shapeLayer.path
        let fromContour = auraLayer.presentation()?.path ?? auraLayer.path
        expanded = value
        stopMotion()
        needsLayout = true
        layoutSubtreeIfNeeded()

        let targetShape = shapePath(expanded: value, amount: restingAmount)
        let targetContour = contourPath(expanded: value, amount: restingAmount)
        setModelPaths(shape: targetShape, contour: targetContour)
        updateContentVisibility(animated: animated)

        guard animated && !reduceMotion, let fromShape, let fromContour else {
            syncMotion()
            completion?()
            return
        }

        let duration = value ? 0.42 : 0.36
        let curve = CAMediaTimingFunction(controlPoints: 0.22, 0.78, 0.28, 1)
        addPathTransition(to: shapeLayer, from: fromShape, to: targetShape, duration: duration, curve: curve)
        addPathTransition(to: auraLayer, from: fromContour, to: targetContour, duration: duration, curve: curve)
        addPathTransition(to: shimmerMask, from: fromContour, to: targetContour, duration: duration, curve: curve)

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, generation == self.transitionGeneration else { return }
            completion?()
            self.syncMotion()
        }
    }

    func prepareForWindowResize() {
        transitionGeneration += 1
        stopMotion()
        shapeLayer.removeAnimation(forKey: "notchTransition")
        auraLayer.removeAnimation(forKey: "notchTransition")
        shimmerMask.removeAnimation(forKey: "notchTransition")
    }

    func stopMotion() {
        pulseIsRunning = false
        shapeLayer.removeAnimation(forKey: "notchBreath")
        auraLayer.removeAnimation(forKey: "notchBreath")
        shimmerMask.removeAnimation(forKey: "notchBreath")
        shimmerLayer.removeAnimation(forKey: "notchShimmer")
    }

    override func layout() {
        super.layout()
        shapeLayer.frame = bounds
        auraLayer.frame = bounds
        shimmerLayer.frame = bounds
        shimmerMask.frame = bounds

        let shape = shapePath(expanded: expanded, amount: restingAmount)
        let contour = contourPath(expanded: expanded, amount: restingAmount)
        setModelPaths(shape: shape, contour: contour)

        let band = NSRect(x: 0, y: 2, width: bounds.width, height: expanded ? 27 : 0)
        let iconSize: CGFloat = 20
        let gap: CGFloat = label.stringValue.isEmpty ? 0 : 7
        let available = max(0, bounds.width - iconSize - gap - 28)
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

    private var restingAmount: CGFloat {
        guard !expanded, activity != .idle else { return 0 }
        return reduceMotion ? 2.5 : 1.5
    }

    private func updateContentVisibility(animated: Bool) {
        let alpha: CGFloat = expanded ? 1 : 0
        guard animated && !reduceMotion else {
            iconView.alphaValue = alpha
            label.alphaValue = alpha
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = expanded ? 0.24 : 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            iconView.animator().alphaValue = alpha
            label.animator().alphaValue = alpha
        }
    }

    private func updateAccent() {
        let leading: NSColor
        let highlight: NSColor
        switch activity {
        case .permission:
            leading = NSColor(srgbRed: 1, green: 0.62, blue: 0.12, alpha: 1)
            highlight = NSColor(srgbRed: 1, green: 0.88, blue: 0.43, alpha: 1)
        case .active:
            leading = NSColor(srgbRed: 0.32, green: 0.62, blue: 1, alpha: 1)
            highlight = NSColor(srgbRed: 0.65, green: 0.42, blue: 1, alpha: 1)
        case .idle:
            leading = .clear
            highlight = .clear
        }

        auraLayer.strokeColor = leading.withAlphaComponent(activity == .idle ? 0 : 0.34).cgColor
        auraLayer.shadowColor = leading.cgColor
        auraLayer.shadowOpacity = activity == .idle ? 0 : (reduceMotion ? 0.18 : 0.42)
        shimmerLayer.colors = [
            leading.withAlphaComponent(0).cgColor,
            leading.withAlphaComponent(0.28).cgColor,
            highlight.withAlphaComponent(0.95).cgColor,
            leading.withAlphaComponent(0.18).cgColor,
            leading.withAlphaComponent(0).cgColor
        ]
        shimmerLayer.locations = [0, 0.32, 0.5, 0.68, 1]
        shimmerLayer.opacity = activity == .idle ? 0 : 1
    }

    private func syncMotion() {
        let shouldPulse = !expanded && activity != .idle && !reduceMotion && bounds.width > 0
        if !shouldPulse {
            pulseIsRunning = false
            return
        }
        guard !pulseIsRunning else { return }
        pulseIsRunning = true

        let low: CGFloat = 1.5
        let high: CGFloat = activity == .permission ? 5.2 : 4.6
        let shapeValues = [
            shapePath(expanded: false, amount: low),
            shapePath(expanded: false, amount: high),
            shapePath(expanded: false, amount: low)
        ]
        let contourValues = [
            contourPath(expanded: false, amount: low),
            contourPath(expanded: false, amount: high),
            contourPath(expanded: false, amount: low)
        ]
        let duration = activity == .permission ? 1.75 : 2.25
        addBreath(to: shapeLayer, values: shapeValues, duration: duration)
        addBreath(to: auraLayer, values: contourValues, duration: duration)
        addBreath(to: shimmerMask, values: contourValues, duration: duration)

        let shimmer = CABasicAnimation(keyPath: "locations")
        shimmer.fromValue = [-0.65, -0.42, -0.2, 0.02, 0.25]
        shimmer.toValue = [0.75, 0.98, 1.2, 1.42, 1.65]
        shimmer.duration = activity == .permission ? 2.1 : 3.1
        shimmer.repeatCount = .infinity
        shimmer.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        shimmerLayer.add(shimmer, forKey: "notchShimmer")
    }

    private func addBreath(to layer: CALayer, values: [CGPath], duration: CFTimeInterval) {
        let animation = CAKeyframeAnimation(keyPath: "path")
        animation.values = values
        animation.keyTimes = [0, 0.5, 1]
        animation.timingFunctions = [
            CAMediaTimingFunction(controlPoints: 0.45, 0, 0.25, 1),
            CAMediaTimingFunction(controlPoints: 0.45, 0, 0.25, 1)
        ]
        animation.duration = duration
        animation.repeatCount = .infinity
        layer.add(animation, forKey: "notchBreath")
    }

    private func addPathTransition(to layer: CALayer, from: CGPath, to: CGPath,
                                   duration: CFTimeInterval, curve: CAMediaTimingFunction) {
        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = curve
        layer.add(animation, forKey: "notchTransition")
    }

    private func setModelPaths(shape: CGPath, contour: CGPath) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeLayer.path = shape
        auraLayer.path = contour
        auraLayer.shadowPath = contour
        shimmerMask.path = contour
        CATransaction.commit()
    }

    /// Uses the same command topology for collapsed and expanded shapes so Core Animation can
    /// interpolate the contour without dropping a frame or flashing a rectangular backing layer.
    private func shapePath(expanded: Bool, amount: CGFloat) -> CGPath {
        let notchWidth = min(physicalNotchWidth, bounds.width)
        let topLeft = round(bounds.midX - notchWidth / 2)
        let topRight = topLeft + notchWidth
        let bodyWidth = expanded ? max(notchWidth, bounds.width - 4) : notchWidth
        let left = round(bounds.midX - bodyWidth / 2)
        let right = left + bodyWidth
        // Extend behind the screen edge to avoid an antialiased seam above the physical cutout.
        let top = bounds.maxY + 2
        let base = expanded ? 2 : max(2, bounds.maxY - bodyHeight)
        let radius: CGFloat = expanded ? 16 : (hasPhysicalNotch ? 12 : 14)
        let shoulder = expanded ? min(top - 4, bounds.maxY - bodyHeight + 8) : base + radius
        let center = (left + right) / 2

        let path = CGMutablePath()
        path.move(to: CGPoint(x: topLeft, y: top))
        path.addLine(to: CGPoint(x: topRight, y: top))
        path.addLine(to: CGPoint(x: topRight, y: shoulder))
        path.addCurve(
            to: CGPoint(x: right, y: base + radius),
            control1: CGPoint(x: topRight, y: shoulder - 8),
            control2: CGPoint(x: right, y: base + radius + 10)
        )
        path.addQuadCurve(
            to: CGPoint(x: right - radius, y: base),
            control: CGPoint(x: right, y: base)
        )
        path.addCurve(
            to: CGPoint(x: center, y: base - amount),
            control1: CGPoint(x: right - bodyWidth * 0.22, y: base),
            control2: CGPoint(x: center + bodyWidth * 0.18, y: base - amount)
        )
        path.addCurve(
            to: CGPoint(x: left + radius, y: base),
            control1: CGPoint(x: center - bodyWidth * 0.18, y: base - amount),
            control2: CGPoint(x: left + bodyWidth * 0.22, y: base)
        )
        path.addQuadCurve(
            to: CGPoint(x: left, y: base + radius),
            control: CGPoint(x: left, y: base)
        )
        path.addCurve(
            to: CGPoint(x: topLeft, y: shoulder),
            control1: CGPoint(x: left, y: base + radius + 10),
            control2: CGPoint(x: topLeft, y: shoulder - 8)
        )
        path.closeSubpath()
        return path
    }

    private func contourPath(expanded: Bool, amount: CGFloat) -> CGPath {
        let notchWidth = min(physicalNotchWidth, bounds.width)
        let topLeft = round(bounds.midX - notchWidth / 2)
        let topRight = topLeft + notchWidth
        let bodyWidth = expanded ? max(notchWidth, bounds.width - 4) : notchWidth
        let left = round(bounds.midX - bodyWidth / 2)
        let right = left + bodyWidth
        let base = expanded ? 2 : max(2, bounds.maxY - bodyHeight)
        let radius: CGFloat = expanded ? 16 : (hasPhysicalNotch ? 12 : 14)
        let shoulder = expanded ? min(bounds.maxY - 2, bounds.maxY - bodyHeight + 8) : base + radius
        let center = (left + right) / 2

        let path = CGMutablePath()
        path.move(to: CGPoint(x: topLeft, y: shoulder))
        path.addCurve(
            to: CGPoint(x: left, y: base + radius),
            control1: CGPoint(x: topLeft, y: shoulder - 8),
            control2: CGPoint(x: left, y: base + radius + 10)
        )
        path.addQuadCurve(
            to: CGPoint(x: left + radius, y: base),
            control: CGPoint(x: left, y: base)
        )
        path.addCurve(
            to: CGPoint(x: center, y: base - amount),
            control1: CGPoint(x: left + bodyWidth * 0.22, y: base),
            control2: CGPoint(x: center - bodyWidth * 0.18, y: base - amount)
        )
        path.addCurve(
            to: CGPoint(x: right - radius, y: base),
            control1: CGPoint(x: center + bodyWidth * 0.18, y: base - amount),
            control2: CGPoint(x: right - bodyWidth * 0.22, y: base)
        )
        path.addQuadCurve(
            to: CGPoint(x: right, y: base + radius),
            control: CGPoint(x: right, y: base)
        )
        path.addCurve(
            to: CGPoint(x: topRight, y: shoulder),
            control1: CGPoint(x: right, y: base + radius + 10),
            control2: CGPoint(x: topRight, y: shoulder - 8)
        )
        return path
    }
}
