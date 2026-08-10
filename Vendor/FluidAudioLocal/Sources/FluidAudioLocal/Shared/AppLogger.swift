// Derived from FluidAudio 0.15.5 at revision
// 19600a485baa4998812e4654b70d2bab8f2c9949, licensed under Apache-2.0.
// Modified for VoxHearth: 2026-08-10. Replaced every logging backend with a
// no-op sink. Message autoclosures are deliberately never evaluated or stored.

/// Source-compatible sink for retained FluidAudio ASR call sites.
///
/// VoxHearth does not permit dependency code to emit or retain arbitrary log
/// content. The autoclosures make interpolated messages lazy, and the empty
/// implementations ensure that their content is never materialized.
public struct AppLogger: Sendable {
    public init(subsystem _: String, category _: String) {}

    public init(category _: String) {}

    public func debug(_: @autoclosure () -> String) {}

    public func info(_: @autoclosure () -> String) {}

    public func notice(_: @autoclosure () -> String) {}

    public func warning(_: @autoclosure () -> String) {}

    public func error(_: @autoclosure () -> String) {}

    public func fault(_: @autoclosure () -> String) {}
}
