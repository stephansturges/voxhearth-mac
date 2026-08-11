import AppKit
import SwiftUI
import VoxHearthCore

struct SettingsRootView: View {
    @Bindable var model: VoxHearthFrontendModel

    var body: some View {
        TabView(selection: $model.selectedSettingsSection) {
            DictationSettingsView(model: model)
                .tabItem { Label("Dictation", systemImage: "waveform") }
                .tag(SettingsSection.dictation)

            PrivacySettingsView(model: model)
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
                .tag(SettingsSection.privacy)

            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsSection.about)

            LicensesView()
                .tabItem { Label("Licenses", systemImage: "doc.text") }
                .tag(SettingsSection.licenses)
        }
        .padding(20)
        .frame(width: 650, height: 520)
        .onAppear {
            ApplicationPresentation.presentSettingsAfterOpening()
            model.refreshPermissionStatus()
        }
    }
}

private struct DictationSettingsView: View {
    @Bindable var model: VoxHearthFrontendModel

    var body: some View {
        Form {
            Section("Hold to talk") {
                LabeledContent("Shortcut") {
                    HotkeyRecorderView(
                        hotkey: model.hotkeyDescriptor,
                        onChange: model.setHotkey
                    )
                    .frame(width: 290)
                }

                LabeledContent("Mouse or accessory") {
                    PointerButtonRecorderView(
                        buttonNumber: model.settings.pointerButton,
                        displayName: model.pointerButtonDisplayName,
                        onChange: model.setPointerButton
                    )
                    .frame(width: 360)
                }

                LabeledContent("Behavior") {
                    Text("Hold to record, release to transcribe")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Speech") {
                Picker("Speech model", selection: transcriptionModelBinding) {
                    ForEach(TranscriptionModel.allCases) { speechModel in
                        Text(speechModel.displayName).tag(speechModel)
                    }
                }
                .disabled(!canChangeSpeechModel)

                Text(model.settings.transcriptionModel.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Microphone", selection: inputDeviceBinding) {
                    Text("System Default").tag("")
                    ForEach(model.availableMicrophones) { device in
                        Text(device.name).tag(device.uid)
                    }
                }

                if let microphoneFallbackNotice = model.microphoneFallbackNotice {
                    Label(microphoneFallbackNotice, systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("Language", selection: languageBinding) {
                    ForEach(model.settings.transcriptionModel.supportedLanguages) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .disabled(model.settings.transcriptionModel == .compactEnglish)

                HStack {
                    Spacer()
                    Button("Refresh microphones") {
                        Task { await model.refreshMicrophones() }
                    }
                    .font(.caption)
                }
            }

            Section("Mac") {
                Toggle("Launch VoxHearth at login", isOn: launchAtLoginBinding)
            }

            Section {
                HStack(spacing: 8) {
                    Image(systemName: model.sessionState.symbolName)
                        .foregroundStyle(model.sessionState.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.sessionState.title)
                            .font(.subheadline.weight(.semibold))
                        Text(model.sessionState.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var inputDeviceBinding: Binding<String> {
        Binding(
            get: { model.settings.inputDeviceUID ?? "" },
            set: { model.setInputDevice(uid: $0.isEmpty ? nil : $0) }
        )
    }

    private var languageBinding: Binding<DictationLanguage> {
        Binding(
            get: { model.settings.language },
            set: { model.setLanguage($0) }
        )
    }

    private var transcriptionModelBinding: Binding<TranscriptionModel> {
        Binding(
            get: { model.settings.transcriptionModel },
            set: { model.setTranscriptionModel($0) }
        )
    }

    private var canChangeSpeechModel: Bool {
        switch model.controller.state {
        case .idle, .failed: true
        case .preparing, .recording, .transcribing, .inserting: false
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { model.settings.launchAtLogin },
            set: { model.setLaunchAtLogin($0) }
        )
    }
}

private struct PrivacySettingsView: View {
    @Bindable var model: VoxHearthFrontendModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Label("Local-only runtime", systemImage: "house.fill")
                        .font(.title3.bold())
                        .foregroundStyle(Color.voxHearthAmber)
                    Text("The model is bundled with the app. VoxHearth has no cloud mode, account, telemetry, plugin registry, or automatic update connection.")
                        .foregroundStyle(.secondary)
                }

                privacyCard(
                    "What VoxHearth handles",
                    text: "Microphone audio is kept only for the active dictation. The resulting text is inserted without creating a VoxHearth transcript or audio history."
                )
                privacyCard(
                    "Where the boundary ends",
                    text: "The destination app receives the text you dictate. It may store or transmit that text according to its own settings and privacy policy."
                )

                accessibilityRecoveryCard

                VStack(alignment: .leading, spacing: 9) {
                    Toggle("Allow clipboard compatibility fallback", isOn: clipboardBinding)
                        .fontWeight(.semibold)
                    Label(
                        "Off by default. When enabled, incompatible apps may receive text through the system clipboard. Clipboard managers and Universal Clipboard may observe it before restoration.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        model.settings.clipboardCompatibilityEnabled
                            ? Color.orange
                            : Color.secondary
                    )
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Preferences stored on this Mac")
                        .font(.subheadline.weight(.semibold))
                    Text("Shortcut, selected microphone identifier, speech model, language, launch-at-login choice, clipboard compatibility choice, and onboarding completion.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Review privacy onboarding") {
                    let settingsWindow = NSApplication.shared.keyWindow
                    model.restartOnboarding()
                    openWindow(id: "onboarding")
                    settingsWindow?.close()
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
            }
            .padding(4)
        }
    }

    private var clipboardBinding: Binding<Bool> {
        Binding(
            get: { model.settings.clipboardCompatibilityEnabled },
            set: { model.setClipboardCompatibility($0) }
        )
    }

    private var accessibilityRecoveryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: model.accessibilityPermission.symbolName)
                    .foregroundStyle(
                        model.accessibilityPermission == .granted
                            ? Color.green
                            : Color.orange
                    )
                Text("Accessibility")
                    .font(.headline)
                Spacer()
                Text(model.accessibilityPermission.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text("VoxHearth needs Accessibility permission to insert dictated text into the app you are using.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text(AccessibilityRecoveryGuidance.updateExplanation)
                .font(.callout.weight(.medium))

            VStack(alignment: .leading, spacing: 4) {
                ForEach(
                    Array(AccessibilityRecoveryGuidance.recoverySteps.enumerated()),
                    id: \.offset
                ) { index, step in
                    Text("\(index + 1). \(step)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button(
                    model.accessibilityPermission == .granted
                        ? "Open Accessibility Settings"
                        : "Set Up Accessibility",
                    action: model.openAccessibilitySettings
                )
                .buttonStyle(.borderedProminent)

                Button("Refresh Status", action: model.refreshPermissionStatus)
                    .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
    }

    private func privacyCard(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
    }
}

private struct AboutView: View {
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 26)
                    .fill(Color.voxGraphite)
                    .frame(width: 112, height: 112)
                Image(systemName: "waveform")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(Color.voxHearthAmber)
            }
            Text("VoxHearth")
                .font(.largeTitle.bold())
            Text("Dictation that stays home.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Fast, open-source dictation for Apple silicon. No cloud, no account, no telemetry.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 410)
            Text(versionText)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
            Spacer()
            Text("A privacy-focused fork of TypeWhisper, distributed under GPL-3.0-or-later.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 28)
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "Version \(version) (\($0))" } ?? "Version \(version)"
    }
}

private struct LicensesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                license(
                    "VoxHearth and TypeWhisper",
                    terms: "GNU General Public License v3.0 or later",
                    note: "VoxHearth preserves the upstream copyright and source-availability obligations."
                )
                license(
                    "FluidAudio",
                    terms: "Apache License 2.0",
                    note: "Provides the native Core ML audio inference runtime."
                )
                license(
                    "Parakeet TDT v3 Core ML model",
                    terms: "Creative Commons Attribution 4.0",
                    note: "Derived from NVIDIA Parakeet and redistributed with attribution in the release notices."
                )
                license(
                    "Parakeet TDT-CTC 110M Core ML model",
                    terms: "Creative Commons Attribution 4.0",
                    note: "The compact English model is derived from NVIDIA Parakeet and redistributed with attribution in the release notices."
                )

                Divider()
                Text("The complete license texts, upstream notices, model provenance, and source offer ship with every release and are available in the repository.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(4)
        }
    }

    private func license(_ name: String, terms: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(name).font(.headline)
            Text(terms)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.voxHearthAmber)
            Text(note)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
    }
}
