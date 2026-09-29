import AppKit

struct ScreenPick: Sendable {
    var point: CGPoint
    var rect: CGRect

    var isRegion: Bool {
        rect.width >= 8 && rect.height >= 8
    }

    var axRect: CGRect? {
        guard isRegion else { return nil }
        let top = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.maxY
            ?? NSScreen.main?.frame.maxY
            ?? rect.maxY
        return CGRect(
            x: rect.minX,
            y: top - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}

@MainActor
final class RegionCaptureController {
    static let shared = RegionCaptureController()

    private var overlays: [CaptureOverlayWindow] = []
    private var island: InstructionIslandPanel?
    private var continuation: CheckedContinuation<ScreenPick?, Never>?
    private var hiddenWindows: [NSWindow] = []
    private var previousApp: NSRunningApplication?
    private var keyMonitor: Any?
    private var didFinish = false

    func pickRegion() async -> ScreenPick? {
        guard continuation == nil else { return nil }
        didFinish = false
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            start()
        }
    }

    func cancel() {
        finish(pick: nil, activatePrevious: true)
    }

    func restoreHiddenWindows() {
        hiddenWindows.forEach { $0.orderFront(nil) }
        hiddenWindows = []
    }

    fileprivate func complete(pick: ScreenPick) {
        guard !didFinish else { return }
        didFinish = true
        dismissOverlay()
        previousApp?.activate()
        Task {
            try? await Task.sleep(for: .milliseconds(90))
            continuation?.resume(returning: pick)
            continuation = nil
        }
    }

    private func start() {
        let parseID = Bundle.main.bundleIdentifier
        previousApp = NSWorkspace.shared.frontmostApplication.flatMap { app in
            app.bundleIdentifier == parseID ? nil : app
        }
        hiddenWindows = NSApp.windows.filter { window in
            window.isVisible && window.level == .normal
        }
        hiddenWindows.forEach { $0.orderOut(nil) }

        NSApp.activate(ignoringOtherApps: true)

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            finish(pick: nil, activatePrevious: true)
            return
        }

        overlays = screens.map { screen in
            let overlay = CaptureOverlayWindow(screen: screen, controller: self)
            overlay.orderFrontRegardless()
            return overlay
        }
        overlays.first?.makeKey()
        if island == nil {
            island = InstructionIslandPanel()
        }
        island?.present()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.cancel()
                return nil
            }
            return event
        }
    }

    private func finish(pick: ScreenPick?, activatePrevious: Bool) {
        guard continuation != nil else { return }
        didFinish = true
        dismissOverlay()
        restoreHiddenWindows()
        if activatePrevious {
            previousApp?.activate()
        }
        continuation?.resume(returning: pick)
        continuation = nil
    }

    private func dismissOverlay() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        overlays.forEach { $0.orderOut(nil) }
        overlays = []
        island?.dismiss()
    }
}

@MainActor
final class CaptureOverlayWindow: NSPanel {
    init(screen: NSScreen, controller: RegionCaptureController) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        setFrame(screen.frame, display: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        animationBehavior = .none
        contentView = CaptureOverlayView(controller: controller)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class CaptureOverlayView: NSView {
    private weak var controller: RegionCaptureController?
    private var dragStart: CGPoint?
    private var currentPoint: CGPoint?
    private var hoverField: CGRect?
    private var lastHoverPoint: CGPoint = .zero
    private var tracking: NSTrackingArea?

    init(controller: RegionCaptureController) {
        self.controller = controller
        super.init(frame: .zero)
        wantsLayer = true
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
        resetTracking()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        resetTracking()
    }

    private var selectionRect: CGRect? {
        guard let dragStart, let currentPoint else { return nil }
        return CGRect(
            x: min(dragStart.x, currentPoint.x),
            y: min(dragStart.y, currentPoint.y),
            width: abs(currentPoint.x - dragStart.x),
            height: abs(currentPoint.y - dragStart.y)
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        let dim = NSColor.black.withAlphaComponent(0.42)
        let path = NSBezierPath(rect: bounds)
        if let selectionRect, selectionRect.width > 2, selectionRect.height > 2 {
            path.append(NSBezierPath(rect: selectionRect))
        }
        if let hover = hoverFieldInView, hover.width > 8, hover.height > 8 {
            path.append(NSBezierPath(roundedRect: hover, xRadius: 6, yRadius: 6))
        }
        if let hole = islandHole, hole.width > 8, hole.height > 8 {
            path.append(NSBezierPath(roundedRect: hole, xRadius: ParseTheme.islandCornerRadius, yRadius: ParseTheme.islandCornerRadius))
        }
        path.windingRule = .evenOdd
        dim.setFill()
        path.fill()

        if let hover = hoverFieldInView, hover.width > 8, hover.height > 8 {
            NSColor.controlAccentColor.withAlphaComponent(0.95).setStroke()
            let border = NSBezierPath(roundedRect: hover.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            border.lineWidth = 2
            border.stroke()
        }

        if let selectionRect, selectionRect.width > 2, selectionRect.height > 2 {
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: selectionRect.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        currentPoint = dragStart
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        hoverField = nil
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.arrow.set()
        guard dragStart == nil, let window else { return }
        let screenPoint = window.convertPoint(toScreen: event.locationInWindow)
        updateHover(at: screenPoint)
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.arrow.set()
        guard dragStart == nil, let window else { return }
        let screenPoint = window.convertPoint(toScreen: event.locationInWindow)
        updateHover(at: screenPoint)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseExited(with event: NSEvent) {
        if hoverField != nil {
            hoverField = nil
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
        guard let window, let currentPoint else {
            controller?.cancel()
            return
        }
        let windowPoint = convert(currentPoint, to: nil)
        let screenPoint = window.convertPoint(toScreen: windowPoint)
        if let selectionRect, selectionRect.width >= 8, selectionRect.height >= 8 {
            let screenRect = window.convertToScreen(convert(selectionRect, to: nil))
            let center = CGPoint(x: screenRect.midX, y: screenRect.midY)
            controller?.complete(pick: ScreenPick(point: center, rect: screenRect))
        } else {
            controller?.complete(pick: ScreenPick(point: screenPoint, rect: CGRect(origin: screenPoint, size: .zero)))
        }
    }

    private var hoverFieldInView: CGRect? {
        guard let hoverField, let window else { return nil }
        return convert(window.convertFromScreen(hoverField), from: nil)
    }

    private func updateHover(at cocoaPoint: CGPoint) {
        if hypot(cocoaPoint.x - lastHoverPoint.x, cocoaPoint.y - lastHoverPoint.y) < 3, hoverField != nil {
            return
        }
        lastHoverPoint = cocoaPoint
        let next = EditorLocator.editorHighlight(atCocoa: cocoaPoint)
        if next != hoverField {
            hoverField = next
            needsDisplay = true
        }
    }

    private var islandHole: CGRect? {
        guard let window, let screen = window.screen else { return nil }
        let visible = screen.visibleFrame
        let size = ParseTheme.islandSize
        let cocoa = CGRect(
            x: visible.midX - size.width / 2,
            y: visible.minY + ParseTheme.islandScreenOffset,
            width: size.width,
            height: size.height
        ).insetBy(dx: -2, dy: -2)
        let windowRect = window.convertFromScreen(cocoa)
        return convert(windowRect, from: nil)
    }

    private func resetTracking() {
        if let tracking {
            removeTrackingArea(tracking)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }
}
