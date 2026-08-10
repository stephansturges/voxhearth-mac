import Testing
@testable import VoxHearthCore

@Test func productIdentityIsIsolatedFromUpstream() {
    #expect(AppIdentity.name == "VoxHearth")
    #expect(AppIdentity.bundleIdentifier == "com.stephansturges.voxhearth")
    #expect(AppIdentity.minimumMacOSMajorVersion == 14)
}
