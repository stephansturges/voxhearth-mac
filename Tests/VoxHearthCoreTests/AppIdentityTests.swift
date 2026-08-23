import Foundation
import Testing
@testable import VoxHearthCore

@Test func productIdentityIsIsolatedFromUpstream() {
    #expect(AppIdentity.name == "VoxHearth")
    #expect(AppIdentity.bundleIdentifier == "com.stephansturges.voxhearth")
    #expect(AppIdentity.minimumMacOSMajorVersion == 14)
}

@Test func signpostIntervalsUseIndependentIdentifiers() throws {
    let signposter = PrivacySafeSignposter(category: "SignpostIdentityTest")
    let first = signposter.begin(.activationHandlingStarted)
    let second = signposter.begin(.audioCaptureStartEntered)
    defer {
        signposter.end(.audioCaptureStarted, first)
        signposter.end(.audioCaptureStarted, second)
    }

    let encoder = JSONEncoder()
    #expect(try encoder.encode(first) != encoder.encode(second))
}
