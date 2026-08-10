import AppKit
import SwiftUI
import VoxHearthCore

@main
@MainActor
struct VoxHearthApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = VoxHearthFrontendModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(model: model)
        } label: {
            Image(systemName: model.sessionState.symbolName)
                .accessibilityLabel("\(AppIdentity.name): \(model.sessionState.title)")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsRootView(model: model)
        }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        .terminateNow
    }
}
