import AppKit
import Observation
import SwiftUI
import VoxHearthCore

enum LiveTranscriptOverlayPresentation {
    static let maximumVisibleWords = 10

    static func displayText(for transcript: String) -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Listening for speech…" }
        let words = trimmed.split(whereSeparator: \.isWhitespace)
        let latestWords = words.suffix(maximumVisibleWords).joined(separator: " ")
        return words.count > maximumVisibleWords ? "… " + latestWords : latestWords
    }
}

struct OverlayPresentationDecision: Equatable {
    let applyText: Bool
    let present: Bool
    let reposition: Bool
}

enum OverlayPresentationPolicy {
    static func decide(
        isVisible: Bool,
        currentText: String,
        incomingText: String
    ) -> OverlayPresentationDecision {
        OverlayPresentationDecision(
            applyText: currentText != incomingText,
            present: !isVisible,
            reposition: !isVisible
        )
    }
}

@Observable
@MainActor
private final class LiveTranscriptOverlayState {
    var text = "Listening for speech…"
    var isVisible = false
}

/// A passive, memory-only overlay. Unlike Notification Center, this panel does
/// not create notification history and never becomes the key window.
@MainActor
final class LiveTranscriptOverlayController: NSObject {
    private let state = LiveTranscriptOverlayState()
    private let panel: PassiveTranscriptPanel
    private let logger = PrivacySafeLogger(category: "Overlay")

    override init() {
        panel = PassiveTranscriptPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(rootView: LiveTranscriptOverlayView(state: state))
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func update(transcript: String?) {
        guard let transcript else {
            guard panel.isVisible else { return }
            state.isVisible = false
            panel.orderOut(nil)
            logger.info(.overlayHidden)
            return
        }

        let displayText = LiveTranscriptOverlayPresentation.displayText(for: transcript)
        let decision = OverlayPresentationPolicy.decide(
            isVisible: panel.isVisible,
            currentText: state.text,
            incomingText: displayText
        )
        if decision.applyText {
            state.text = displayText
            logger.info(.overlayTextApplied)
        }
        guard decision.present else { return }

        state.isVisible = true
        if decision.reposition {
            positionOnActiveScreen()
        }
        logger.info(.overlayOrderFrontStarted)
        panel.orderFrontRegardless()
        logger.info(.overlayOrderFrontCompleted)
    }

    private func positionOnActiveScreen() {
        logger.info(.overlayScreenQueryStarted)
        let pointer = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let screen = screens.first(where: { $0.frame.contains(pointer) })
            ?? NSScreen.main
            ?? screens.first
        logger.info(.overlayScreenQueryCompleted)
        guard let visibleFrame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(
            NSPoint(
                x: visibleFrame.maxX - size.width - 20,
                y: visibleFrame.maxY - size.height - 20
            )
        )
        logger.info(.overlayPositionApplied)
    }

    @objc private func screenParametersDidChange() {
        guard panel.isVisible else { return }
        positionOnActiveScreen()
    }
}

private final class PassiveTranscriptPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct LiveTranscriptOverlayView: View {
    @Bindable var state: LiveTranscriptOverlayState

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "waveform")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.voxHearthAmber)

            Text(state.text)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Image(systemName: "house.fill")
                .font(.caption)
                .foregroundStyle(Color.voxHearthAmber.opacity(0.8))
                .accessibilityLabel("On-device preview")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .foregroundStyle(Color.voxWarmWhite)
        .background(Color.voxGraphite.opacity(0.96), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.voxHearthAmber.opacity(0.42), lineWidth: 1)
        }
        .padding(2)
    }
}
