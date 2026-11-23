import Foundation
import Testing
@testable import ShimaCore

struct UpdateInvocationTests {
    private let stage = URL(fileURLWithPath: "/Applications/.shima-update-12345678-1234-1234-1234-123456789ABC")
    private var arguments: [String] { ["ShimaUpdater", "2", "/Applications/Shima.app", stage.path] }

    @Test func acceptsExactProductionTargetSiblingUUIDAndParentPID() throws {
        let value = try #require(UpdateInvocation.parse(arguments: arguments, resolvedStage: { stage }))
        #expect(value.parentPID == 2)
        #expect(value.target.path == "/Applications/Shima.app")
        #expect(value.stage == stage)
    }

    @Test func requiresExactlyFourArguments() {
        for args in [[], Array(arguments.prefix(3)), arguments + ["extra"]] {
            #expect(UpdateInvocation.parse(arguments: args, resolvedStage: { stage }) == nil)
        }
    }

    @Test(arguments: ["", "pid", "0", "1", "-1", "2147483648", "2.0"])
    func rejectsInvalidParentPID(_ pid: String) {
        var args = arguments
        args[1] = pid
        #expect(UpdateInvocation.parse(arguments: args, resolvedStage: { stage }) == nil)
    }

    @Test func acceptsInt32MaximumPID() {
        var args = arguments
        args[1] = String(Int32.max)
        #expect(UpdateInvocation.parse(arguments: args, resolvedStage: { stage })?.parentPID == Int32.max)
    }

    @Test(arguments: ["/Applications/Other.app", "/Applications/Shima.app/", "/Applications/./Shima.app", "/applications/Shima.app", "/repo/Shima.app"])
    func requiresExactProductionTarget(_ target: String) {
        var args = arguments
        args[2] = target
        #expect(UpdateInvocation.parse(arguments: args, resolvedStage: { stage }) == nil)
    }

    @Test(arguments: ["/Applications/.shima-update-invalid", "/Applications/.shima-update-", "/Applications/shima-update-12345678-1234-1234-1234-123456789ABC", "/Applications/.shima-update-12345678-1234-1234-1234-123456789ABC-extra", "/Applications/nested/.shima-update-12345678-1234-1234-1234-123456789ABC", "/other/.shima-update-12345678-1234-1234-1234-123456789ABC"])
    func requiresSiblingStageWithUUID(_ path: String) {
        var args = arguments
        args[3] = path
        #expect(UpdateInvocation.parse(arguments: args, resolvedStage: { URL(fileURLWithPath: path) }) == nil)
    }

    @Test func rejectsSymlinkResolutionOfEitherStageOrParentDirectory() {
        for resolved in [URL(fileURLWithPath: "/Applications/elsewhere"), URL(fileURLWithPath: "/actual-apps/\(stage.lastPathComponent)")] {
            #expect(UpdateInvocation.parse(arguments: arguments, resolvedStage: { resolved }) == nil)
        }
    }

    @Test func testingTargetIsAnExplicitExactOverride() {
        let target = "/repo/fixture/Shima.app"
        let fixtureStage = URL(fileURLWithPath: "/repo/fixture/\(stage.lastPathComponent)")
        let args = ["helper-test", "99999999", target, fixtureStage.path]
        #expect(UpdateInvocation.parse(arguments: args, resolvedStage: { fixtureStage }) == nil)
        #expect(UpdateInvocation.parse(arguments: args, resolvedStage: { fixtureStage }, expectedTarget: target)?.target.path == target)
        #expect(UpdateInvocation.parse(arguments: args, resolvedStage: { fixtureStage }, expectedTarget: "") == nil)
    }

    @Test func rejectsInvalidArgumentsBeforeResolvingAnyFilesystemPath() {
        for invalid in [["helper", "1", "/Applications/Shima.app", stage.path],
                        ["helper", "2", "/repo/Shima.app", stage.path],
                        ["helper", "2", "/Applications/Shima.app", "/Applications/not-a-stage"],
                        []] {
            var resolutions = 0
            let value = UpdateInvocation.parse(arguments: invalid, resolvedStage: {
                resolutions += 1
                return stage
            })
            #expect(value == nil)
            #expect(resolutions == 0)
        }
    }
}
