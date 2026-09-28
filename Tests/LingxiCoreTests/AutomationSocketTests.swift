import Foundation
import Darwin
import Testing
@testable import LingxiCore

struct AutomationProtocolTests {
    @Test func wireEncodingIsStableAndUsesPublicKeys() throws {
        let request = AutomationRequest(requestID: "r1", method: "status", params: .object(["b": .bool(true), "a": .array([.null, .number(3)])]))
        let encoded = try AutomationJSON.encode(request)
        #expect(String(decoding: encoded, as: UTF8.self) == "{\"method\":\"status\",\"params\":{\"a\":[null,3],\"b\":true},\"request_id\":\"r1\",\"version\":1}")
        #expect(try AutomationJSON.decode(AutomationRequest.self, from: encoded) == request)
        let response = AutomationResponse.success(request: request, result: .string("ok"), replayed: true)
        #expect(try AutomationJSON.decode(AutomationResponse.self, from: AutomationJSON.encode(response)) == response)
        #expect(JSONValue.number(.infinity).intValue == nil)
        #expect(JSONValue.number(2.5).intValue == nil)
        #expect(JSONValue.number(Double(Int.max)).intValue == nil)
    }

    @Test func datesUseISO8601WithMillisecondsAndAcceptWholeSeconds() throws {
        struct Stamp: Codable { let date: Date }
        let whole = try AutomationJSON.decode(Stamp.self, from: Data("{\"date\":\"2026-09-17T12:00:00+08:00\"}".utf8))
        let fraction = try AutomationJSON.decode(Stamp.self, from: Data("{\"date\":\"2026-09-17T04:00:00.125Z\"}".utf8))
        #expect(abs(fraction.date.timeIntervalSince(whole.date) - 0.125) < 0.0001)
        #expect(String(decoding: try AutomationJSON.encode(fraction), as: UTF8.self).contains("04:00:00.125Z"))
        #expect(throws: DecodingError.self) { try AutomationJSON.decode(Stamp.self, from: Data("{\"date\":123}".utf8)) }
        for invalid in ["2026-02-30T09:00:00Z", "2026-09-17T09:00:00Zgarbage", "2026-09-17T09:00:00+25:00",
                        "2026-09-17T24:00:00Z", "2026-09-17T09:00:60Z", "2025-02-29T09:00:00Z", "2026-09-17T09:00:00"] {
            #expect(throws: DecodingError.self) {
                try AutomationJSON.decode(Stamp.self, from: Data("{\"date\":\"\(invalid)\"}".utf8))
            }
        }
        let leap = try AutomationJSON.decode(Stamp.self, from: Data("{\"date\":\"2024-02-29T12:34:56.789-05:30\"}".utf8))
        #expect(String(decoding: try AutomationJSON.encode(leap), as: UTF8.self).contains("2024-02-29T18:04:56.789Z"))
    }
}

@Suite(.serialized)
struct AutomationSocketTests {
    private func fixture() throws -> (String, URL) {
        let directory = URL(fileURLWithPath: "/tmp/lingxi-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return (directory.appendingPathComponent("test.sock").path, directory)
    }

    @Test func sameUserClientReachesInjectedHandlerAndEndpointIsPrivate() throws {
        let (path, directory) = try fixture()
        let server = AutomationSocketServer(path: path) { request in .success(request: request, result: request.params) }
        defer { server.stop(); try? FileManager.default.removeItem(at: directory) }
        try server.start()
        let request = AutomationRequest(requestID: "read-1", method: "status", params: .object(["hello": .string("灵性日历")]))
        let response = try AutomationSocket.send(request, path: path)
        #expect(response.ok)
        #expect(response.result == request.params)
        var info = stat()
        #expect(lstat(path, &info) == 0)
        #expect(info.st_uid == getuid())
        #expect(info.st_mode & 0o777 == 0o600)
        #expect(lstat(directory.path, &info) == 0)
        #expect(info.st_mode & 0o777 == 0o700)
    }

    @Test func activeEndpointIsNotReplacedAndOtherFilesAreNotRemoved() throws {
        let (path, directory) = try fixture()
        let first = AutomationSocketServer(path: path) { .success(request: $0, result: .string("first")) }
        let second = AutomationSocketServer(path: path) { .success(request: $0, result: .string("second")) }
        defer { first.stop(); second.stop(); try? FileManager.default.removeItem(at: directory) }
        try first.start()
        #expect(throws: AutomationTransportError.self) { try second.start() }
        second.stop()
        #expect(try AutomationSocket.send(AutomationRequest(method: "status"), path: path).result == .string("first"))
        first.stop()
        try Data("owned-file".utf8).write(to: URL(fileURLWithPath: path))
        let replacement = AutomationSocketServer(path: path) { .success(request: $0, result: .null) }
        #expect(throws: AutomationTransportError.self) { try replacement.start() }
        #expect(try String(contentsOfFile: path) == "owned-file")
    }

    @Test func missingAppWrongProtocolAndOversizedRequestsHaveSpecificFailures() throws {
        let (path, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            _ = try AutomationSocket.send(AutomationRequest(method: "status"), path: path)
            Issue.record("Missing endpoint unexpectedly accepted a request")
        } catch let error as AutomationTransportError { #expect(error.code == "app_not_running") }
        let server = AutomationSocketServer(path: path) { .success(request: $0, result: .null) }
        defer { server.stop() }
        try server.start()
        let failure = try AutomationSocket.send(AutomationRequest(version: 2, method: "status"), path: path)
        #expect(failure.error?.code == "unsupported_version")
        let invalid = try AutomationSocket.send(AutomationRequest(method: "status", params: .array([])), path: path)
        #expect(invalid.error?.code == "invalid_params")
        #expect(throws: AutomationTransportError.self) {
            try AutomationSocket.send(AutomationRequest(method: "status", params: .string(String(repeating: "a", count: AutomationSocket.maximumRequestBytes))), path: path)
        }
    }

    @Test func symlinkEndpointAndDirectoryAreRejected() throws {
        let (path, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target")
        try Data("keep".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: target.path)
        let server = AutomationSocketServer(path: path) { .success(request: $0, result: .null) }
        #expect(throws: AutomationTransportError.self) { try server.start() }
        #expect(throws: AutomationTransportError.self) { try AutomationSocket.send(AutomationRequest(method: "status"), path: path) }
        #expect(try String(contentsOf: target) == "keep")
        let linked = directory.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(atPath: linked.path, withDestinationPath: directory.path)
        let other = AutomationSocketServer(path: linked.appendingPathComponent("other.sock").path) { .success(request: $0, result: .null) }
        #expect(throws: AutomationTransportError.self) { try other.start() }
    }

    @Test func clientTimeoutDoesNotAbandonAnAcceptedMutation() async throws {
        let (path, directory) = try fixture()
        let effect = SocketEffectCounter()
        let server = AutomationSocketServer(path: path) { request in
            await effect.begin()
            try? await Task.sleep(nanoseconds: 120_000_000)
            await effect.finish()
            return .success(request: request, result: .bool(true))
        }
        defer { server.stop(); try? FileManager.default.removeItem(at: directory) }
        try server.start()
        do {
            _ = try AutomationSocket.send(AutomationRequest(requestID: "timeout-test", method: "synthetic.write"), path: path, timeout: 0.03)
            Issue.record("A deliberately slow handler should time out at the client")
        } catch let error as AutomationTransportError { #expect(error.code == "transport_timeout") }
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(await effect.completed == 1)
    }

    @Test func concurrentClientsAreDeliveredSequentially() async throws {
        let (path, directory) = try fixture()
        let effect = SocketEffectCounter()
        let server = AutomationSocketServer(path: path) { request in
            await effect.begin()
            try? await Task.sleep(nanoseconds: 10_000_000)
            await effect.finish()
            return .success(request: request, result: .bool(true))
        }
        defer { server.stop(); try? FileManager.default.removeItem(at: directory) }
        try server.start()
        try await withThrowingTaskGroup(of: Bool.self) { group in
            for index in 0..<4 {
                group.addTask { try AutomationSocket.send(AutomationRequest(requestID: "parallel-\(index)", method: "status"), path: path).ok }
            }
            for try await result in group { #expect(result) }
        }
        #expect(await effect.completed == 4)
        #expect(await effect.maximumActive == 1)
    }
}

private actor SocketEffectCounter {
    var active = 0
    var maximumActive = 0
    var completed = 0
    func begin() { active += 1; maximumActive = max(maximumActive, active) }
    func finish() { active -= 1; completed += 1 }
}
