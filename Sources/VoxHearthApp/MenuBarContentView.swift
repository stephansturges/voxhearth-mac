import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @Bindable var model: VoxHearthFrontendModel
    @Environment(\.openSettings) private var openSettings

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
        VStack(alignment: .leading, spacing: 16) {
            header
            statusCard

            if model.hasPendingTranscript {
                recoveryCard
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

            if case .listening = model.sessionState {
                Button("Cancel Dictation", role: .cancel, action: model.cancelDictation)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
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
                .symbolEffect(.pulse, isActive: model.sessionState.isBusy)
                .foregroundStyle(model.sessionState.tint)
                .frame(width: 28)

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

    private var recoveryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Text was not inserted", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.voxHearthAmber)

            Text("Your transcript is held only in memory for up to two minutes. Retry after choosing a text field, or discard it now.")
                .font(.caption)
                .foregroundStyle(Color.voxWarmWhite.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Retry insertion", action: model.retryPendingInsertion)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.voxHearthAmber)
                    .foregroundStyle(Color.voxGraphite)
                Button("Discard", role: .destructive, action: model.discardPendingTranscript)
                    .buttonStyle(.bordered)
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

    private var primaryActionSymbol: String {
        switch model.sessionState {
        case .listening: "stop.fill"
        case .transcribing: "ellipsis"
        case .idle, .error: "mic.fill"
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
    }
}
