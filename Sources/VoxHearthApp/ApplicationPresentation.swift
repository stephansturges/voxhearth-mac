import AppKit

@MainActor
enum ApplicationPresentation {
    /// SwiftUI may create or reveal the Settings scene after `openSettings()`
    /// returns. Retry briefly so the user-initiated window reliably becomes
    /// key/front even though VoxHearth normally runs as an accessory app.
    static func presentSettingsAfterOpening() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        Task { @MainActor in
            await bringSettingsWindowForward()
            try? await Task.sleep(for: .milliseconds(120))
            await bringSettingsWindowForward()
        }
    }

    static func bringSettingsWindowForward() async {
        await Task.yield()
        let application = NSApplication.shared
        application.activate(ignoringOtherApps: true)

        let candidates = application.windows.filter { window in
            window.isVisible
                && window.canBecomeKey
                && window.styleMask.contains(.titled)
                && !(window is NSPanel)
                && window.title != "Welcome to VoxHearth"
        }
        let settingsWindow = candidates.first {
            $0.title.localizedCaseInsensitiveContains("settings")
        } ?? candidates.first

        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
    }

    static func openAccessibilitySettings() -> Bool {
        NSWorkspace.shared.open(AccessibilityRecoveryGuidance.settingsURL)
    }
}
