import AppKit
import SwiftUI
import VoxHearthCore

struct MenuBarContentView: View {
    @Bindable var model: VoxHearthFrontendModel
    @Environment(\.openSettings) private var openSettings
    @State private var recoveryConfirmation: RecoveryConfirmation?

    var body: some View {
        Group {
            if model.hasCompletedOnboarding {
                mainMenu
            } else {
                OnboardingView(model: model)
            }
        }
        .frame(width: model.hasCompletedOnboarding ? 360 : 520)
        .background(Color.voxGraphite)
        .foregroundStyle(Color.voxWarmWhite)
    }

    private var mainMenu: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                statusCard

                ForEach(model.pendingInsertionPresentations) { pending in
                    recoveryCard(pending)
                }

                if let recoveryNotice = model.recoveryNotice {
                    Text(recoveryNotice)
                        .font(.caption)
                        .foregroundStyle(Color.voxWarmWhite.opacity(0.74))
                        .accessibilityLabel(recoveryNotice)
                }

                Button(action: model.primaryDictationAction) {
                    HStack {
                        Image(systemName: primaryActionSymbol)
                        Text(model.sessionState.primaryActionTitle)
                        Spacer()
                        Text(model.settings.hotkey.displayName)
                            .font(.caption.monospaced())
                            .opacity(0.72)
                    }
                    .fontWeight(.semibold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .foregroundStyle(Color.voxGraphite)
                    .background(Color.voxHearthAmber, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(model.sessionState.isBusy)

                quickControls

                if model.sessionState.canCancelCurrentSession {
                    Button("Cancel Dictation", role: .cancel, action: model.cancelDictation)
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .keyboardShortcut(.cancelAction)
                        .accessibilityLabel("Cancel the current dictation without inserting text")
                }

                Divider().overlay(Color.voxWarmWhite.opacity(0.18))

                VStack(spacing: 2) {
                    menuRow("Settings", symbol: "gearshape") {
                        showSettings(.dictation)
                    }
                    menuRow("Privacy", symbol: "hand.raised") {
                        showSettings(.privacy)
                    }
                    menuRow("About VoxHearth", symbol: "info.circle") {
                        showSettings(.about)
                    }
                    menuRow("Licenses", symbol: "doc.text") {
                        showSettings(.licenses)
                    }
                    menuRow("Quit VoxHearth", symbol: "power") {
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
            .padding(18)
        }
        .frame(maxHeight: 720)
        .confirmationDialog(
            recoveryConfirmation?.title ?? "Confirm recovery action",
            isPresented: Binding(
                get: { recoveryConfirmation != nil },
                set: { if !$0 { recoveryConfirmation = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let confirmation = recoveryConfirmation {
                Button(confirmation.actionTitle, role: confirmation.role) {
                    perform(confirmation)
                    recoveryConfirmation = nil
                }
                Button("Cancel", role: .cancel) {
                    recoveryConfirmation = nil
                }
            }
        } message: {
            Text(recoveryConfirmation?.message ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.voxHearthAmber)
                    .frame(width: 42, height: 42)
                Image(systemName: "waveform")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Color.voxGraphite)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("VoxHearth")
                    .font(.headline)
                Text("Dictation that stays home.")
                    .font(.caption)
                    .foregroundStyle(Color.voxWarmWhite.opacity(0.68))
            }
            Spacer()
            Label("Local", systemImage: "house.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.voxHearthAmber)
        }
    }

    private var statusCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: model.sessionState.symbolName)
                .font(.title2)
                .foregroundStyle(model.sessionState.tint)
                .frame(width: 28)
                .opacity(model.sessionState.isBusy ? 0 : 1)
                .overlay {
                    if model.sessionState.isBusy {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.voxHearthAmber)
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(model.sessionState.title)
                    .font(.subheadline.weight(.semibold))
                Text(model.sessionState.detail)
                    .font(.caption)
                    .foregroundStyle(Color.voxWarmWhite.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(Color.voxWarmWhite.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private func recoveryCard(_ pending: PendingInsertionPresentation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(pending.title, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.voxHearthAmber)

            Text(pending.detail)
                .font(.caption)
                .foregroundStyle(Color.voxWarmWhite.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Copy") {
                    model.copyPendingInsertion(sessionID: pending.id)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.voxHearthAmber)
                .foregroundStyle(Color.voxGraphite)
                .accessibilityLabel("Copy \(pending.title) to the clipboard")

                if pending.allowsRetry {
                    Button("Retry") {
                        if pending.retryNeedsConfirmation {
                            recoveryConfirmation = .retry(pending)
                        } else {
                            model.retryPendingInsertion(sessionID: pending.id)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.controller.state == .inserting)
                    .accessibilityLabel("Retry inserting \(pending.title)")
                }

                if pending.allowsInsertAnyway {
                    Button("Insert Anyway") {
                        recoveryConfirmation = .insertAnyway(pending)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.controller.state == .inserting)
                    .accessibilityLabel("Insert \(pending.title) once using the clipboard")
                }

                Button("Discard", role: .destructive) {
                    model.discardPendingInsertion(sessionID: pending.id)
                }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Discard \(pending.title) from memory")
            }
        }
        .padding(13)
        .background(Color.voxHearthAmber.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }

    private var quickControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Controls")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.voxWarmWhite.opacity(0.68))

            HotkeyRecorderView(
                hotkey: model.hotkeyDescriptor,
                onChange: model.setHotkey
            )

            Button {
                showSettings(.dictation)
            } label: {
                HStack {
                    Image(systemName: "computermouse")
                    Text(model.pointerButtonDisplayName)
                    Spacer()
                    Text(model.settings.pointerButton == nil ? "Add" : "Change")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Toggle("Launch VoxHearth at login", isOn: launchAtLoginBinding)
                .toggleStyle(.checkbox)
                .font(.callout)

            Toggle("Show live transcript overlay", isOn: liveTranscriptOverlayBinding)
                .toggleStyle(.checkbox)
                .font(.callout)
        }
        .padding(12)
        .background(Color.voxWarmWhite.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { model.settings.launchAtLogin },
            set: { model.setLaunchAtLogin($0) }
        )
    }

    private var liveTranscriptOverlayBinding: Binding<Bool> {
        Binding(
            get: { model.settings.liveTranscriptOverlayEnabled },
            set: { model.setLiveTranscriptOverlay($0) }
        )
    }

    private var primaryActionSymbol: String {
        switch model.sessionState {
        case .listening: "stop.fill"
        case .finalizing, .cleaning, .inserting: "ellipsis"
        case .idle, .error: "mic.fill"
        }
    }

    private func perform(_ confirmation: RecoveryConfirmation) {
        switch confirmation.action {
        case .retry:
            model.retryPendingInsertion(sessionID: confirmation.sessionID)
        case .insertAnyway:
            model.insertPendingAnyway(sessionID: confirmation.sessionID)
        }
    }

    private func menuRow(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .frame(width: 18)
                Text(title)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.voxWarmWhite.opacity(0.9))
    }

    private func showSettings(_ section: SettingsSection) {
        model.selectedSettingsSection = section
        openSettings()
        ApplicationPresentation.presentSettingsAfterOpening()
    }
}

private struct RecoveryConfirmation: Identifiable {
    enum Action {
        case retry
        case insertAnyway
    }

    let id = UUID()
    let sessionID: DictationSessionID
    let title: String
    let message: String
    let actionTitle: String
    let role: ButtonRole?
    let action: Action

    static func retry(_ pending: PendingInsertionPresentation) -> Self {
        Self(
            sessionID: pending.id,
            title: "Retry insertion?",
            message: "VoxHearth could not confirm whether the text was already inserted. Check the destination first; retrying may create a duplicate.",
            actionTitle: "Retry",
            role: nil,
            action: .retry
        )
    }

    static func insertAnyway(_ pending: PendingInsertionPresentation) -> Self {
        Self(
            sessionID: pending.id,
            title: "Insert formatted text anyway?",
            message: pending.insertAnywayWarning,
            actionTitle: "Insert Anyway",
            role: .destructive,
            action: .insertAnyway
        )
    }
}
