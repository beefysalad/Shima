import Foundation

/// The helper's non-destructive argument checks, independent of AppKit and file IO.
public struct UpdateInvocation: Equatable, Sendable {
    public let parentPID: Int32
    public let target: URL
    public let stage: URL

    /// The caller supplies symlink resolution lazily; it runs only after argument and path checks.
    /// Tests may supply a different exact target; production uses only /Applications/Shima.app.
    public static func parse(arguments: [String], resolvedStage: () -> URL,
                             expectedTarget: String = "/Applications/Shima.app") -> Self? {
        guard arguments.count == 4, let pid = Int32(arguments[1]), pid > 1,
              arguments[2] == expectedTarget else { return nil }
        let target = URL(fileURLWithPath: arguments[2])
        let stage = URL(fileURLWithPath: arguments[3])
        guard stage.deletingLastPathComponent() == target.deletingLastPathComponent(),
              stage.lastPathComponent.hasPrefix(".shima-update-"),
              UUID(uuidString: String(stage.lastPathComponent.dropFirst(".shima-update-".count))) != nil,
              resolvedStage() == stage else { return nil }
        return Self(parentPID: pid, target: target, stage: stage)
    }
}
