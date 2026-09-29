import AppKit
import SwiftUI

enum WindowSizing {
    static func fitToScreen(_ window: NSWindow) {
        window.styleMask.formUnion([.titled, .closable, .miniaturizable, .resizable])
        window.minSize = NSSize(width: ParseTheme.minWindowWidth, height: ParseTheme.minWindowHeight)
        window.maxSize = NSSize(width: 10_000, height: 10_000)
        window.isRestorable = true

        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame.insetBy(dx: 24, dy: 24)
        var frame = window.frame
        frame.size.width = min(ParseTheme.defaultWindowWidth, visible.width)
        frame.size.height = min(ParseTheme.defaultWindowHeight, visible.height)
        if frame.width > visible.width { frame.size.width = visible.width }
        if frame.height > visible.height { frame.size.height = visible.height }
        frame.origin.x = visible.midX - frame.width / 2
        frame.origin.y = visible.midY - frame.height / 2
        if frame.maxX > visible.maxX { frame.origin.x = visible.maxX - frame.width }
        if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - frame.height }
        if frame.minX < visible.minX { frame.origin.x = visible.minX }
        if frame.minY < visible.minY { frame.origin.y = visible.minY }
        window.setFrame(frame, display: true)
    }

    static func mainWindow() -> NSWindow? {
        NSApp.windows.first(where: { window in
            window.identifier?.rawValue == "main" || window.title == "Parse"
        }) ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain })
    }
}
