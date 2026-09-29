import AppKit
import SwiftUI

@main
struct ParseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("Parse", id: "main") {
            MainView(session: SessionStore.shared)
                .frame(minWidth: ParseTheme.minWindowWidth, minHeight: ParseTheme.minWindowHeight)
        }
        .defaultSize(width: ParseTheme.defaultWindowWidth, height: ParseTheme.defaultWindowHeight)
        .windowResizability(.contentMinSize)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New") {
                    SessionStore.shared.newSession()
                }
                .keyboardShortcut("n")
            }
            CommandMenu("Code") {
                Button("Select Code to Translate…") {
                    SessionStore.shared.grabFromScreen()
                }
                Button("Copy Code") {
                    SessionStore.shared.copyCode()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("Paste into Parse") {
                    SessionStore.shared.pasteFromClipboard()
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra("Parse", systemImage: "chevron.left.forwardslash.chevron.right") {
            Button("Open Parse") {
                SessionStore.shared.showMainWindow()
            }
            Divider()
            SettingsLink {
                Text("Settings…")
            }
            .simultaneousGesture(TapGesture().onEnded {
                NSApp.activate(ignoringOtherApps: true)
            })
            Divider()
            Button("Quit Parse") {
                NSApp.terminate(nil)
            }
        }

        Settings {
            SettingsView(session: SessionStore.shared)
        }
    }
}
