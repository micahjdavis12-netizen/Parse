import AppKit
import ParseCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        HotKeyCenter.shared.onPressed = {
            SessionStore.shared.grabFromScreen()
        }
        HotKeyCenter.shared.register()

        NSApp.servicesProvider = ParseServiceProvider()
        NSUpdateDynamicServices()
        AppleFoundationProvider.prewarmIfPossible()

        DispatchQueue.main.async {
            SessionStore.shared.showMainWindow()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        HotKeyCenter.shared.register()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SessionStore.shared.showMainWindow()
        return true
    }
}

final class ParseServiceProvider: NSObject {
    @objc func explainWithParse(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let text = pboard.string(forType: .string)
            ?? pboard.string(forType: .rtf)
            ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        DispatchQueue.main.async {
            SessionStore.shared.loadPasted(text)
            SessionStore.shared.showMainWindow()
        }
    }
}
