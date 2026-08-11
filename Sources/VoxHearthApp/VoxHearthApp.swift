import AppKit
import SwiftUI
import VoxHearthCore

@main
@MainActor
struct VoxHearthApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = VoxHearthFrontendModel()

    var body: some Scene {
        Window("Welcome to VoxHearth", id: "onboarding") {
            OnboardingWindowView(model: model)
        }
        .defaultSize(width: 520, height: 455)
        .windowResizability(.contentSize)

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
private struct OnboardingWindowView: View {
    @Bindable var model: VoxHearthFrontendModel
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Group {
            if !model.hasCompletedOnboarding {
                OnboardingView(model: model)
                    .frame(width: 520)
                    .background(Color.voxGraphite)
                    .foregroundStyle(Color.voxWarmWhite)
                    .onAppear {
                        ApplicationPresentation.presentOnboardingAfterOpening()
                    }
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
                    .onAppear(perform: dismissOnboardingWindow)
            }
        }
        .onChange(of: model.hasCompletedOnboarding) { _, completed in
            if completed {
                dismissOnboardingWindow()
            }
        }
    }

    private func dismissOnboardingWindow() {
        dismissWindow(id: "onboarding")
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? AppIdentity.bundleIdentifier
        let runningProcessIdentifiers = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .map(\.processIdentifier)

        if AppInstancePolicy.shouldTerminateNewInstance(
            currentProcessIdentifier: currentProcessIdentifier,
            runningProcessIdentifiers: runningProcessIdentifiers
        ) {
            NSApplication.shared.terminate(nil)
            return
        }

        NSApplication.shared.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        .terminateNow
    }
}
