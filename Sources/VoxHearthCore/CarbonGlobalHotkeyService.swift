import Carbon.HIToolbox
import Foundation

public enum GlobalHotkeyError: Error, Equatable, Sendable {
    case registrationFailed(OSStatus)
    case handlerInstallationFailed(OSStatus)
}

private let voxHearthHotkeyHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var hotkeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotkeyID
    )
    guard status == noErr, hotkeyID.id == CarbonGlobalHotkeyService.hotkeyID else {
        return OSStatus(eventNotHandledErr)
    }

    let service = Unmanaged<CarbonGlobalHotkeyService>
        .fromOpaque(userData)
        .takeUnretainedValue()
    let phase: GlobalHotkeyPhase
    switch GetEventKind(event) {
    case UInt32(kEventHotKeyPressed):
        phase = .pressed
    case UInt32(kEventHotKeyReleased):
        phase = .released
    default:
        return OSStatus(eventNotHandledErr)
    }
    if Thread.isMainThread {
        // Application-target Carbon handlers run on the main event loop. Avoid
        // adding a second queued hop, which can turn a busy SwiftUI frame into
        // visible press/release latency.
        MainActor.assumeIsolated {
            service.handle(phase)
        }
    } else {
        // Keep a defensive fallback in case Carbon ever changes delivery
        // context rather than making an unsafe actor assumption.
        Task { @MainActor in
            service.handle(phase)
        }
    }
    return noErr
}

/// Registers one system-wide Carbon hotkey. Carbon hotkeys do not inspect or
/// retain keyboard input and therefore avoid an event-tap key logger surface.
public final class CarbonGlobalHotkeyService: GlobalHotkeyRegistering, @unchecked Sendable {
    nonisolated fileprivate static let hotkeyID: UInt32 = 1
    nonisolated private static let signature: OSType = 0x5648_4B59 // "VHKY"

    // Carbon references are created/mutated on MainActor. `nonisolated(unsafe)`
    // also lets deinit synchronously unregister them before `userData` expires.
    nonisolated(unsafe) private var hotkeyReference: EventHotKeyRef?
    nonisolated(unsafe) private var handlerReference: EventHandlerRef?
    private var onEvent: (@MainActor @Sendable (GlobalHotkeyPhase) -> Void)?
    private var isKeyDown = false
    private let logger = PrivacySafeLogger(category: "Hotkey")

    public init() {}

    deinit {
        if let hotkeyReference {
            UnregisterEventHotKey(hotkeyReference)
        }
        if let handlerReference {
            RemoveEventHandler(handlerReference)
        }
    }

    @MainActor
    public func register(
        _ configuration: HotkeyConfiguration,
        onEvent: @escaping @MainActor @Sendable (GlobalHotkeyPhase) -> Void
    ) throws {
        unregister()
        self.onEvent = onEvent

        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            ),
        ]
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            voxHearthHotkeyHandler,
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerReference
        )
        guard handlerStatus == noErr else {
            handlerReference = nil
            self.onEvent = nil
            throw GlobalHotkeyError.handlerInstallationFailed(handlerStatus)
        }

        let identifier = EventHotKeyID(
            signature: Self.signature,
            id: Self.hotkeyID
        )
        let registrationStatus = RegisterEventHotKey(
            configuration.keyCode,
            Self.carbonModifiers(for: configuration.modifiers),
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotkeyReference
        )
        guard registrationStatus == noErr else {
            if let handlerReference {
                RemoveEventHandler(handlerReference)
            }
            handlerReference = nil
            hotkeyReference = nil
            self.onEvent = nil
            throw GlobalHotkeyError.registrationFailed(registrationStatus)
        }
    }

    @MainActor
    public func unregister() {
        if let hotkeyReference {
            UnregisterEventHotKey(hotkeyReference)
            self.hotkeyReference = nil
        }
        if let handlerReference {
            RemoveEventHandler(handlerReference)
            self.handlerReference = nil
        }
        onEvent = nil
        isKeyDown = false
    }

    @MainActor
    fileprivate func handle(_ phase: GlobalHotkeyPhase) {
        switch phase {
        case .pressed:
            guard !isKeyDown else { return }
            isKeyDown = true
            logger.info(.hotkeyPressed)
        case .released:
            guard isKeyDown else { return }
            isKeyDown = false
            logger.info(.hotkeyReleased)
        }
        onEvent?(phase)
    }

    nonisolated static func carbonModifiers(for modifiers: HotkeyModifiers) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }
}
