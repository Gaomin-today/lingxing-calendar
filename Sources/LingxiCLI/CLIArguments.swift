import Foundation
import LingxiCore

struct CLIArguments {
    var preview = false
    var help = false
    var skillPath = false
    var request: AutomationRequest?

    static let methods: [String: Set<String>] = [
        "profiles": ["list", "show", "create", "update", "delete"],
        "chart": ["show"], "luck": ["show"], "calendar": ["day"],
        "events": ["list", "show", "create", "update", "delete"], "tasks": ["list", "show", "complete"],
        "journal": ["list", "show", "create", "update", "delete"],
        "insights": ["list", "show", "save", "delete"], "knowledge": ["search", "read"],
        "open": ["day", "chart", "event", "journal"]
    ]

    static func parse(_ arguments: [String], input: (String) throws -> Data) throws -> Self {
        var output = Self()
        var positionals: [String] = []
        var values: [String: JSONValue] = [:]
        var file: String?
        var requestID: String?
        var cursor = 0
        func add(_ key: String, _ value: JSONValue) throws {
            guard !key.isEmpty, values[key] == nil else { throw usage("参数 \(key) 重复。") }
            values[key] = value
        }
        while cursor < arguments.count {
            let item = arguments[cursor]; cursor += 1
            switch item {
            case "--help", "-h": output.help = true
            case "--preview": output.preview = true
            case "--json": break // JSON is always the wire and output format.
            default:
                if item.hasPrefix("--") {
                    let pair = String(item.dropFirst(2)).split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    let key = String(pair[0])
                    let value: String
                    if pair.count == 2 { value = String(pair[1]) }
                    else {
                        guard cursor < arguments.count, !arguments[cursor].hasPrefix("--") else { throw usage("\(item) 缺少参数值。") }
                        value = arguments[cursor]; cursor += 1
                    }
                    switch key {
                    case "input":
                        guard file == nil else { throw usage("只能指定一次 --input。") }; file = value
                    case "request-id":
                        guard requestID == nil, !value.isEmpty, value.utf8.count <= 128,
                              value.unicodeScalars.allSatisfy({ !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.controlCharacters.contains($0) }) else {
                            throw usage("--request-id 必须是 1–128 字节、无空白或控制字符的唯一编号，且不能重复指定。")
                        }
                        requestID = value
                    case "param":
                        let parameter = value.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                        guard parameter.count == 2 else { throw usage("--param 使用 KEY=JSON 格式。") }
                        do { try add(String(parameter[0]), AutomationJSON.decode(JSONValue.self, from: Data(parameter[1].utf8))) }
                        catch let error as AutomationTransportError { throw error }
                        catch { throw usage("--param 的值必须是有效 JSON；字符串需用 JSON 引号。") }
                    default:
                        if ["limit", "offset", "year", "month", "day", "hour", "minute", "count"].contains(key) {
                            guard let number = Int(value) else { throw usage("--\(key) 需要整数。") }
                            try add(key, .number(Double(number)))
                        } else { try add(key, .string(value)) }
                    }
                } else { positionals.append(item) }
            }
        }
        if output.help || positionals.isEmpty || positionals == ["help"] { output.help = true; return output }
        if positionals == ["skill", "path"] {
            guard values.isEmpty, file == nil, requestID == nil else { throw usage("skill path 不接受业务参数。") }
            output.skillPath = true; return output
        }
        let method: String
        if positionals.count == 1, ["status", "capabilities", "context"].contains(positionals[0]) {
            method = positionals[0] == "context" ? "context.day" : positionals[0]
        } else if positionals.count == 2, methods[positionals[0]]?.contains(positionals[1]) == true {
            method = positionals.joined(separator: ".")
        } else { throw usage("未知命令：\(positionals.joined(separator: " "))。使用 --help 查看命令。") }
        if let file {
            let data = try input(file)
            guard data.count <= AutomationSocket.maximumRequestBytes else { throw usage("--input 文件超过 1 MiB 上限。") }
            let decoded: JSONValue
            do { decoded = try AutomationJSON.decode(JSONValue.self, from: data) }
            catch { throw usage("--input 必须包含有效 JSON 参数对象。") }
            guard let object = decoded.objectValue else { throw usage("--input 必须是参数对象，不能是数组或完整请求信封。") }
            guard Set(object.keys).isDisjoint(with: values.keys) else {
                throw usage("--input 与命令行参数包含重名键，请只保留一种来源。")
            }
            values.merge(object) { old, _ in old }
        }
        let action = method.split(separator: ".").last.map(String.init) ?? method
        if ["create", "update", "delete", "save", "complete"].contains(action), requestID == nil {
            throw usage("写入命令必须提供 --request-id；超时重试时请保持同一个编号。")
        }
        output.request = AutomationRequest(requestID: requestID, method: method, params: .object(values))
        return output
    }

    static func usage(_ message: String) -> AutomationTransportError { AutomationTransportError("invalid_arguments", message) }
}

let cliHelp = """
灵性日历 CLI · 本机接口 version 1

用法：lingxi [--preview] <命令> [参数] [--input FILE|-]

  status | capabilities              查看应用状态与能力
  context --profile ID --date YYYY-MM-DD
  profiles list|show|create|update|delete
  chart show | luck show | calendar day
  events list|show|create|update|delete | tasks list|show|complete
  journal list|show|create|update|delete
  insights list|show|save|delete
  knowledge search|read
  open day|chart|event|journal
  skill path                         显示应用随附的 Skill 路径

参数：
  --profile ID --date YYYY-MM-DD --id ID --from DATE --to DATE
  --revision REV --query TEXT --limit N
  --input FILE|-                     JSON 参数对象；- 表示标准输入
  --param KEY=JSON                    显式传递 JSON 类型的单个参数
  --request-id ID                     所有写入命令必需；重试请复用编号
  --preview                          连接隔离预览应用

普通 --key VALUE 原样传递字符串；year/month/day/hour/minute/count/limit/offset
传整数。复杂字段请使用 --input 或 --param。重名参数会报错，不会覆盖。
日期范围、字段格式及版本要求以 capabilities 和随附 Skill 为准。
业务输出为 JSON；应用必须先运行，CLI 不直接改文件、不自动启动或联网。
退出码：0 成功，2 参数/协议错误，3 应用不可用/通信失败，4 操作失败，5 版本冲突。
"""
