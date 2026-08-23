import AppKit
import VoxHearthCore

enum RecoveryAccessibilityAnnouncement {
    case copied
    case copyFailed
    case discarded
}

@MainActor
enum ApplicationPresentation {
    static func announce(_ progress: DictationProgress) {
        let announcement: String?
        switch progress {
        case .finalizing:
            announcement = nil
        case let .cleaning(format):
            announcement = CleanupProgressPresentation.cleaningDetail(for: format)
        case let .fallingBack(format, reason):
            announcement = CleanupProgressPresentation.fallbackDetail(
                format: format,
                reason: reason
            )
        case let .formattedTextReady(reason):
            announcement = reason == .insertionUncertain
                ? "Insertion could not be confirmed. Check the destination before retrying. The text is available in the VoxHearth menu-bar popover for 2 minutes."
                : "Formatted text ready. Open the VoxHearth menu-bar popover to copy or insert it. Available for 2 minutes."
        }
        guard let announcement else { return }
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: announcement,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }

    static func announceRecovery(_ event: RecoveryAccessibilityAnnouncement) {
        let announcement = switch event {
        case .copied:
            "Copied. The text remains on the clipboard."
        case .copyFailed:
            "The text could not be copied."
        case .discarded:
            "The in-memory dictation was discarded."
        }
        postAnnouncement(announcement)
    }

    private static func postAnnouncement(_ announcement: String) {
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: announcement,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }

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

    static func revealApplicationInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    static func presentOnboardingAfterOpening() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        Task { @MainActor in
            await bringOnboardingWindowForward()
            try? await Task.sleep(for: .milliseconds(120))
            await bringOnboardingWindowForward()
        }
    }

    private static func bringOnboardingWindowForward() async {
        await Task.yield()
        let application = NSApplication.shared
        application.activate(ignoringOtherApps: true)
        let onboardingWindow = application.windows.first {
            $0.isVisible
                && $0.canBecomeKey
                && $0.title == "Welcome to VoxHearth"
        }
        onboardingWindow?.makeKeyAndOrderFront(nil)
        onboardingWindow?.orderFrontRegardless()
    }
}
