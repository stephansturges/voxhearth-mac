import Foundation
import LlamaLocal

public enum LlamaBackend: String, Equatable, Sendable {
    case cpu
    case metal
}

public struct LlamaBackendCapabilities: Equatable, Sendable {
    public let hasMetalDevice: Bool
    public let hasSealedMetalLibrary: Bool

    public init(hasMetalDevice: Bool, hasSealedMetalLibrary: Bool) {
        self.hasMetalDevice = hasMetalDevice
        self.hasSealedMetalLibrary = hasSealedMetalLibrary
    }
}

public struct LlamaBackendSelection: Sendable {
    public let selected: LlamaBackend
    public let capabilities: LlamaBackendCapabilities

    public init(capabilities: LlamaBackendCapabilities) {
        selected = capabilities.hasMetalDevice && capabilities.hasSealedMetalLibrary
            ? .metal
            : .cpu
        self.capabilities = capabilities
    }

    public static func production(
        resourceURL: URL? = Bundle.main.resourceURL
    ) -> LlamaBackendSelection {
        let metalURL = resourceURL?
            .appendingPathComponent("Metal", isDirectory: true)
            .appendingPathComponent("ggml-llama.metallib", isDirectory: false)
        let sealedLibraryExists: Bool
        if let metalURL,
           let values = try? metalURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) {
            sealedLibraryExists = values.isRegularFile == true && values.isSymbolicLink != true
        } else {
            sealedLibraryExists = false
        }

        let hasMetalDevice = LlamaRuntime.shared.hasDevice(ofType: GGML_BACKEND_DEVICE_TYPE_GPU)
        let capabilities = LlamaBackendCapabilities(
            hasMetalDevice: hasMetalDevice,
            hasSealedMetalLibrary: sealedLibraryExists
        )
        return LlamaBackendSelection(capabilities: capabilities)
    }
}
