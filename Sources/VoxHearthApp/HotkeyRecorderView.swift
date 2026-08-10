import AppKit
import SwiftUI

struct HotkeyRecorderView: View {
    let hotkey: HotkeyDescriptor
    let onChange: (HotkeyDescriptor) -> Void

    @State private var isRecording = false
    @State private var eventMonitor: Any?
    @State private var validationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isRecording ? "keyboard.badge.ellipsis" : "keyboard")
                    Text(isRecording ? "Press a shortcut…" : hotkey.displayName)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                    Spacer(minLength: 16)
                    Text(isRecording ? "Cancel" : "Change")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)

            Text(validationMessage ?? "Hold the shortcut while speaking; release it to transcribe.")
                .font(.caption)
                .foregroundStyle(validationMessage == nil ? Color.secondary : Color.red)
        }
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        stopRecording()
        validationMessage = nil
        isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }

            let descriptor = HotkeyDescriptor(
                keyCode: event.keyCode,
                modifierRawValue: event.modifierFlags
                    .intersection(.deviceIndependentFlagsMask)
                    .rawValue
            )
            guard descriptor.isSuitableGlobalShortcut else {
                validationMessage = "Include Control, Option, or Command in the shortcut."
                NSSound.beep()
                return nil
            }

            onChange(descriptor)
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
