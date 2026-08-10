import AppKit
import Foundation

/// Observes only `otherMouseDown` and `otherMouseUp`, then forwards the one
/// configured button. It never observes pointer movement, scrolling, primary
/// clicks, secondary clicks, or keyboard input.
public final class GlobalPointerButtonService: GlobalPointerButtonRegistering, @unchecked Sendable {
    nonisolated(unsafe) private var globalMonitor: Any?
    nonisolated(unsafe) private var localMonitor: Any?
    private var buttonNumber: UInt32?
    private var onEvent: (@MainActor @Sendable (GlobalHotkeyPhase) -> Void)?
    private var isButtonDown = false

    public init() {}

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    @MainActor
    public func register(
        buttonNumber: UInt32?,
        onEvent: @escaping @MainActor @Sendable (GlobalHotkeyPhase) -> Void
    ) {
        unregister()
        guard let buttonNumber, buttonNumber >= 2 else { return }

        self.buttonNumber = buttonNumber
        self.onEvent = onEvent
        let mask: NSEvent.EventTypeMask = [.otherMouseDown, .otherMouseUp]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    @MainActor
    public func unregister() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        buttonNumber = nil
        onEvent = nil
        isButtonDown = false
    }

    @MainActor
    private func handle(_ event: NSEvent) {
        guard UInt32(event.buttonNumber) == buttonNumber else { return }
        switch event.type {
        case .otherMouseDown:
            guard !isButtonDown else { return }
            isButtonDown = true
            onEvent?(.pressed)
        case .otherMouseUp:
            guard isButtonDown else { return }
            isButtonDown = false
            onEvent?(.released)
        default:
            break
        }
    }
}
