import SwiftUI

struct OnboardingView: View {
    @Bindable var model: VoxHearthFrontendModel
    @State private var testText = ""
    @FocusState private var testFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingHeader

            Group {
                switch model.onboardingStep {
                case .privacy:
                    privacyStep
                case .permissions:
                    permissionsStep
                case .tryIt:
                    tryItStep
                }
            }
            .frame(maxWidth: .infinity, minHeight: 305, alignment: .topLeading)

            Divider().overlay(Color.voxWarmWhite.opacity(0.18))
            navigation
        }
        .padding(22)
        .onAppear {
            model.refreshPermissionStatus()
        }
        .task {
            // Let the setup window become key before macOS presents its own
            // Accessibility prompt, so the two foreground requests do not race.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            model.requestAccessibilityForUpdatedBuildIfNeeded()
        }
    }

    private var onboardingHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("VoxHearth", systemImage: "waveform")
                    .font(.title2.bold())
                    .foregroundStyle(Color.voxHearthAmber)
                Spacer()
                Text("Step \(model.onboardingStep.rawValue + 1) of 3")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.voxWarmWhite.opacity(0.62))
            }

            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                    Capsule()
                        .fill(step.rawValue <= model.onboardingStep.rawValue
                              ? Color.voxHearthAmber
                              : Color.voxWarmWhite.opacity(0.16))
                        .frame(height: 4)
                }
            }

            Text(model.onboardingStep.title)
                .font(.title3.bold())
        }
    }

    private var privacyStep: some View {
        VStack(alignment: .leading, spacing: 13) {
            if model.onboardingLaunchReason == .updatedBuild {
                Label("A new VoxHearth build is installed", systemImage: "arrow.down.app.fill")
                    .font(.headline)
                    .foregroundStyle(Color.voxHearthAmber)
                Text("Please review permissions for this build. Unsigned development updates may need Accessibility authorization again even when the previous version was allowed.")
                    .font(.callout)
                    .foregroundStyle(Color.voxWarmWhite.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("The speech model ships inside VoxHearth. Dictation does not need an account, API key, cloud service, telemetry service, or update connection.")
                .foregroundStyle(Color.voxWarmWhite.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)

            privacyPromise(
                "Processed on this Mac",
                detail: "Microphone audio is held only for the current dictation and processed by the bundled local model.",
                symbol: "desktopcomputer"
            )
            privacyPromise(
                "No VoxHearth history",
                detail: "VoxHearth does not save audio or transcripts after insertion.",
                symbol: "clock.badge.xmark"
            )
            privacyPromise(
                "A clear boundary",
                detail: "The app you dictate into may handle the inserted text under its own privacy policy.",
                symbol: "rectangle.and.hand.point.up.left"
            )
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("VoxHearth asks only for access needed to hear your shortcut and place text where you are typing.")
                .foregroundStyle(Color.voxWarmWhite.opacity(0.82))

            permissionRow(
                title: "Microphone",
                detail: "Records only while dictation is active.",
                symbol: "mic",
                status: model.microphonePermission,
                requestTitle: "Allow Microphone",
                action: model.requestMicrophonePermission
            )
            permissionRow(
                title: "Accessibility",
                detail: model.onboardingLaunchReason == .updatedBuild
                    ? "Reauthorize this build so it can insert text. Remove the old entry first if macOS kept it."
                    : "Inserts the transcript into the focused text field.",
                symbol: "accessibility",
                status: model.accessibilityPermission,
                requestTitle: "Set Up Accessibility",
                action: model.openAccessibilitySettings
            )

            if model.accessibilityPermission != .granted {
                Text("macOS does not let an app add or approve itself in Accessibility. If VoxHearth does not appear after the system prompt, press + in Accessibility Settings and choose it from Applications.")
                    .font(.caption)
                    .foregroundStyle(Color.voxWarmWhite.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)

                Button("Show VoxHearth in Finder", action: model.revealApplicationInFinder)
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.voxHearthAmber)
            }

            if !model.onboardingCanAdvance {
                Button("Refresh permission status", action: model.refreshPermissionStatus)
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.voxHearthAmber)
            }
        }
    }

    private var tryItStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Click the field, hold \(model.settings.hotkey.displayName), speak, then release. Your words should appear below without leaving this Mac.")
                .foregroundStyle(Color.voxWarmWhite.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $testText)
                .font(.body)
                .scrollContentBackground(.hidden)
                .foregroundStyle(Color.voxGraphite)
                .padding(10)
                .background(Color.voxWarmWhite, in: RoundedRectangle(cornerRadius: 10))
                .frame(minHeight: 135)
                .focused($testFieldFocused)
                .overlay(alignment: .topLeading) {
                    if testText.isEmpty {
                        Text("Your local test transcription appears here…")
                            .foregroundStyle(Color.voxGraphite.opacity(0.45))
                            .padding(.horizontal, 15)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: 8) {
                Image(systemName: model.sessionState.symbolName)
                    .foregroundStyle(model.sessionState.tint)
                Text(model.sessionState.title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Button("Focus test field") { testFieldFocused = true }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Color.voxHearthAmber)
            }
        }
        .onAppear { testFieldFocused = true }
    }

    private var navigation: some View {
        HStack {
            if model.onboardingStep != .privacy {
                Button("Back", action: model.moveBackInOnboarding)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.voxWarmWhite.opacity(0.72))
            }
            Spacer()
            Button(model.onboardingStep == .tryIt ? "Start using VoxHearth" : "Continue") {
                model.advanceOnboarding()
            }
            .buttonStyle(.plain)
            .fontWeight(.semibold)
            .foregroundStyle(Color.voxGraphite)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                model.onboardingCanAdvance ? Color.voxHearthAmber : Color.voxWarmWhite.opacity(0.28),
                in: RoundedRectangle(cornerRadius: 9)
            )
            .disabled(!model.onboardingCanAdvance)
        }
    }

    private func privacyPromise(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.voxHearthAmber)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.voxWarmWhite.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.voxWarmWhite.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private func permissionRow(
        title: String,
        detail: String,
        symbol: String,
        status: PermissionPresentation,
        requestTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.voxHearthAmber)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.voxWarmWhite.opacity(0.65))
            }
            Spacer(minLength: 12)
            if status == .granted {
                Label(status.title, systemImage: status.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                Button(requestTitle, action: action)
                    .buttonStyle(.bordered)
                    .tint(Color.voxHearthAmber)
            }
        }
        .padding(12)
        .background(Color.voxWarmWhite.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }
}
