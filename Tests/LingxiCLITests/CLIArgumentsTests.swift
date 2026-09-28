import Foundation
import Testing
import LingxiCore
@testable import LingxiCLI

struct CLIArgumentsTests {
    private func parse(_ arguments: [String], json: String = "{}") throws -> CLIArguments {
        try CLIArguments.parse(arguments) { _ in Data(json.utf8) }
    }

    @Test func readCommandsAreStructuredAndPreviewIsExplicit() throws {
        let result = try parse(["--preview", "context", "--profile", "person", "--date", "2026-09-17", "--limit", "20"])
        #expect(result.preview)
        #expect(result.request?.method == "context.day")
        #expect(result.request?.params["profile"] == .string("person"))
        #expect(result.request?.params["limit"] == .number(20))
        #expect(try parse(["status"]).request?.method == "status")
        #expect(try parse(["knowledge", "read", "--id", "intro"]).request?.params["id"] == .string("intro"))
    }

    @Test func mutationsRequireStableRequestIDs() throws {
        for command in [["profiles", "create"], ["events", "update"], ["tasks", "complete"], ["journal", "delete"], ["insights", "save"]] {
            #expect(throws: AutomationTransportError.self) { try parse(command) }
            #expect(try parse(command + ["--request-id", "retry-1"]).request?.requestID == "retry-1")
        }
        #expect(throws: AutomationTransportError.self) { try parse(["events", "create", "--request-id", " "]) }
    }

    @Test func expandedReadRoutesAndKnowledgePurposeRemainStructured() throws {
        let strength = try parse(["strength", "show", "--profile", "synthetic-profile"])
        #expect(strength.request?.method == "strength.show")
        let hexagrams = try parse(["hexagrams", "show", "--profile", "synthetic-profile", "--date", "2026-09-28", "--at", "12:00"])
        #expect(hexagrams.request?.method == "hexagrams.show")
        #expect(hexagrams.request?.params["at"] == .string("12:00"))
        let search = try parse(["knowledge", "search", "--query", "测试词语", "--purpose", "合成回归核对资料"])
        #expect(search.request?.params["purpose"] == .string("合成回归核对资料"))
        let read = try parse(["knowledge", "read", "--id", "excerpt-synthetic", "--purpose", "合成回归核对资料", "--offset", "800"])
        #expect(read.request?.params["purpose"] == .string("合成回归核对资料"))
        #expect(read.request?.params["offset"] == .number(800))
    }

    @Test func jsonInputMergesOnlyDistinctKeysAndPreservesTypes() throws {
        let result = try parse(["events", "create", "--request-id", "new-1", "--input", "-", "--profile", "p", "--param", "enabled=true"], json: "{\"event\":{\"title\":\"面试\",\"isTask\":false}}")
        #expect(result.request?.params["event"]?["isTask"] == .bool(false))
        #expect(result.request?.params["enabled"] == .bool(true))
        #expect(throws: AutomationTransportError.self) { try parse(["status", "--input", "a", "--id", "b"], json: "{\"id\":\"a\"}") }
        #expect(throws: AutomationTransportError.self) { try parse(["status", "--id", "a", "--id", "b"]) }
        #expect(throws: AutomationTransportError.self) { try parse(["status", "--input", "a"], json: "[]") }
    }

    @Test func malformedCommandsAndMissingValuesFailBeforeConnecting() throws {
        for arguments in [["unknown"], ["events", "wipe"], ["status", "--id"], ["status", "--limit", "many"], ["status", "--param", "bad"], ["status", "--input", "a", "--input", "b"]] {
            #expect(throws: AutomationTransportError.self) { try parse(arguments) }
        }
        #expect(try parse(["--help"]).help)
        #expect(try parse(["skill", "path"]).skillPath)
    }
}
