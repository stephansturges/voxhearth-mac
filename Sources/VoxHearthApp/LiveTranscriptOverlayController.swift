import AppKit
import SwiftUI

enum LiveTranscriptOverlayPresentation {
    static let maximumVisibleCharacters = 260

    static func displayText(for transcript: String) -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Listening for speech…" }
        guard trimmed.count > maximumVisibleCharacters else { return trimmed }

        let suffix = String(trimmed.suffix(maximumVisibleCharacters))
        guard let firstSpace = suffix.firstIndex(where: \.isWhitespace) else {
            return "…" + suffix
        }
        return "…" + suffix[suffix.index(after: firstSpace)...]
    }
}

/// A passive, memory-only overlay. Unlike Notification Center, this panel does
/// not create notification history and never becomes the key window.
@MainActor
final class LiveTranscriptOverlayController {
    private let panel: PassiveTranscriptPanel

    init() {
        panel = PassiveTranscriptPanel(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 154),
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
    }

    func update(transcript: String?) {
        guard let transcript else {
            panel.orderOut(nil)
            panel.contentView = nil
            return
        }

        panel.contentView = NSHostingView(
            rootView: LiveTranscriptOverlayView(
                text: LiveTranscriptOverlayPresentation.displayText(for: transcript)
            )
        )
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
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "waveform")
                    .symbolEffect(.pulse)
                Text("Live preview")
                    .fontWeight(.semibold)
                Spacer()
                Label("On-device", systemImage: "house.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.voxHearthAmber)
            }

            Text(text)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .lineLimit(5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Text("Approximate preview — final inserted text may differ")
                .font(.caption2)
                .foregroundStyle(Color.voxWarmWhite.opacity(0.58))
        }
        .padding(15)
        .foregroundStyle(Color.voxWarmWhite)
        .background(Color.voxGraphite.opacity(0.96), in: RoundedRectangle(cornerRadius: 15))
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .stroke(Color.voxHearthAmber.opacity(0.42), lineWidth: 1)
        }
        .padding(2)
    }
}
