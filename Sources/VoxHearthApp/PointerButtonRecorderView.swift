import AppKit
import SwiftUI

struct PointerButtonRecorderView: View {
    let buttonNumber: UInt32?
    let displayName: String
    let onChange: (UInt32?) -> Void

    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    isRecording ? stopRecording() : startRecording()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isRecording ? "computermouse.fill" : "computermouse")
                        Text(isRecording ? "Press a mouse button…" : displayName)
                            .font(.system(.body, design: .rounded, weight: .semibold))
                        Spacer(minLength: 12)
                        Text(isRecording ? "Cancel" : buttonNumber == nil ? "Add" : "Change")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)

                if buttonNumber != nil, !isRecording {
                    Button("Clear") { onChange(nil) }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Optional. Hold the chosen middle or extra mouse button to dictate. Its normal action may still occur in the focused app.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { event in
            guard event.buttonNumber >= 2 else { return event }
            onChange(UInt32(event.buttonNumber))
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        isRecording = false
    }
}
