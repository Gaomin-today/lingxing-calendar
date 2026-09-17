import Foundation
import Darwin
import LingxiCore

@main
enum LingxiCommand {
    static func main() {
        var request: AutomationRequest?
        do {
            let options = try CLIArguments.parse(Array(CommandLine.arguments.dropFirst())) { path in
                if path == "-" {
                    var data = Data()
                    while true {
                        let part = try FileHandle.standardInput.read(upToCount: 8192) ?? Data()
                        if part.isEmpty { return data }
                        data.append(part)
                        guard data.count <= AutomationSocket.maximumRequestBytes else { throw CLIArguments.usage("标准输入超过 1 MiB 上限。") }
                    }
                }
                let url = URL(fileURLWithPath: path)
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= AutomationSocket.maximumRequestBytes else { throw CLIArguments.usage("输入文件超过 1 MiB 上限。") }
                return try Data(contentsOf: url)
            }
            if options.help { print(cliHelp); return }
            if options.skillPath {
                let executable = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).standardizedFileURL.resolvingSymlinksInPath()
                let resources = executable.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/AgentSkill")
                guard FileManager.default.fileExists(atPath: resources.appendingPathComponent("SKILL.md").path) else {
                    throw AutomationTransportError("skill_not_found", "请使用应用包 Contents/MacOS/lingxi；Skill 位于 Contents/Resources/AgentSkill。")
                }
                emit(.success(request: AutomationRequest(method: "skill.path"), result: .object(["path": .string(resources.path), "skill": .string(resources.appendingPathComponent("SKILL.md").path)])))
                return
            }
            guard let parsed = options.request else { throw CLIArguments.usage("缺少命令。") }
            request = parsed
            let response = try AutomationSocket.send(parsed, path: AutomationSocket.defaultPath(preview: options.preview))
            emit(response)
            if !response.ok { Darwin.exit(exitCode(for: response.error?.code ?? "operation_failed")) }
        } catch let error as AutomationTransportError {
            emit(.failure(request: request, code: error.code, message: error.message))
            Darwin.exit(exitCode(for: error.code))
        } catch {
            emit(.failure(request: request, code: "invalid_arguments", message: "无法读取请求参数：\(error.localizedDescription)"))
            Darwin.exit(2)
        }
    }

    static func emit(_ response: AutomationResponse) {
        if let data = try? AutomationJSON.encode(response) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([10]))
        }
    }
    static func exitCode(for code: String) -> Int32 {
        if ["conflict", "revision_conflict", "profile_revision_conflict", "stale_revision", "request_id_conflict"].contains(code) { return 5 }
        if ["invalid_arguments", "invalid_request", "invalid_params", "unsupported_version", "method_not_found", "request_too_large"].contains(code) { return 2 }
        if ["app_not_running", "socket_unavailable", "unsafe_socket", "peer_not_allowed", "connection_failed", "connection_closed", "transport_timeout", "transport_error", "operation_timeout", "invalid_response", "incomplete_request"].contains(code) { return 3 }
        return 4
    }
}
