import AppKit
import Observation
import SwiftUI

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

@Observable
@MainActor
private final class LiveTranscriptOverlayState {
    var text = "Listening for speech…"
}

/// A passive, memory-only overlay. Unlike Notification Center, this panel does
/// not create notification history and never becomes the key window.
@MainActor
final class LiveTranscriptOverlayController {
    private let state = LiveTranscriptOverlayState()
    private let panel: PassiveTranscriptPanel

    init() {
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
    }

    func update(transcript: String?) {
        guard let transcript else {
            panel.orderOut(nil)
            return
        }

        state.text = LiveTranscriptOverlayPresentation.displayText(for: transcript)
        positionOnActiveScreen()
        panel.orderFrontRegardless()
    }

    private func positionOnActiveScreen() {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(
            NSPoint(
                x: visibleFrame.maxX - size.width - 20,
                y: visibleFrame.maxY - size.height - 20
            )
        )
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
                .symbolEffect(.pulse)
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
