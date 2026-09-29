import AppKit
import SwiftUI

/// Capsule parked just above the Dock. Solid fill so the type stays readable.
@MainActor
final class InstructionIslandPanel: NSPanel {
    private let padding = ParseTheme.islandWindowPadding

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: ParseTheme.islandWindowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none

        let canvas = NSView(frame: NSRect(origin: .zero, size: ParseTheme.islandWindowSize))
        canvas.wantsLayer = true
        canvas.layer?.backgroundColor = NSColor.clear.cgColor

        let plate = NSView(frame: NSRect(
            x: padding,
            y: padding,
            width: ParseTheme.islandSize.width,
            height: ParseTheme.islandSize.height
        ))
        plate.wantsLayer = true
        plate.layer?.backgroundColor = NSColor(srgbRed: 0.18, green: 0.18, blue: 0.19, alpha: 1).cgColor
        plate.layer?.cornerRadius = ParseTheme.islandCornerRadius
        plate.layer?.cornerCurve = .continuous
        plate.layer?.masksToBounds = true
        plate.autoresizingMask = [.width, .height]

        let hostingView = NSHostingView(rootView: SelectIslandView())
        hostingView.frame = plate.bounds
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        plate.addSubview(hostingView)
        canvas.addSubview(plate)
        contentView = canvas
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func reposition() {
        let pointer = NSEvent.mouseLocation
        let pointerScreen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
        guard let screen = pointerScreen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let size = frame.size
        setFrameOrigin(
            NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.minY + ParseTheme.islandScreenOffset - padding
            )
        )
    }

    func present() {
        reposition()
        alphaValue = 1
        orderFrontRegardless()
    }

    func dismiss() {
        alphaValue = 0
        orderOut(nil)
    }
}

private struct SelectIslandView: View {
    var body: some View {
        VStack(spacing: 1) {
            Text("Select code to translate")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text("Click the editor  ·  Esc")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
