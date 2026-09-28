import Foundation
import LingxiCore

public struct AgentSkill: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var description: String
    public var requiredTools: [AgentToolName]
    public var instructions: String
    public var outputSections: [String]

    public init(id: String, title: String, description: String = "", requiredTools: [AgentToolName] = [],
                instructions: String = "", outputSections: [String] = ["结论", "依据", "解读与行动", "边界与不确定性"]) {
        self.id = id
        self.title = title
        self.description = description
        self.requiredTools = requiredTools
        self.instructions = instructions
        self.outputSections = outputSections
    }
}

public struct SkillRegistry: Sendable {
    public private(set) var skills: [AgentSkill]

    public init(skills: [AgentSkill] = [AgentSkill.dailyReading]) { self.skills = skills }

    public mutating func register(_ skill: AgentSkill) {
        guard !skill.id.isEmpty else { return }
        if let index = skills.firstIndex(where: { $0.id == skill.id }) { skills[index] = skill } else { skills.append(skill) }
    }

    public func skill(id: String) -> AgentSkill? { skills.first { $0.id == id } }

    /// Small deterministic classifier; a model may still refine the plan, but
    /// the runtime always validates the selected skill's tool allowlist.
    public func select(for text: String) -> AgentSkill? {
        let value = text.lowercased()
        if let named = skills.first(where: { value.contains($0.id.lowercased()) || value.contains($0.title.lowercased()) }) { return named }
        if value.contains("盘") || value.contains("命") || value.contains("八字") || value.contains("面试") || value.contains("适合") || value.contains("日程") || value.contains("安排") {
            return skills.first(where: { $0.id == AgentSkill.dailyReading.id }) ?? skills.first
        }
        return skills.first
    }
}

public extension AgentSkill {
    static let dailyReading = AgentSkill(
        id: "daily-reading",
        title: "个人日期解读",
        description: "先读取确定性日期、盘面和相关安排，再给出有依据的传统解释与行动建议。",
        // knowledge_read is conditional: the model may only know an entry ID
        // after the search result arrives, so it is not a mandatory first
        // round tool.
        requiredTools: [.dayContext, .eventsContext, .knowledgeSearch],
        instructions: "区分应用事实、传统解释、行动建议和不确定性；不补造未知出生时刻，不把推断写成盘面事实。"
    )
}

public struct AgentConfiguration: Codable, Equatable, Sendable {
    public var soul: String
    public var agent: String
    public var user: String
    public private(set) var hardPolicy: String

    public init(soul: String = "你是灵性日历里的阿灵，温和、清楚、尊重用户的选择。",
                agent: String = "先查确定性事实，再读取必要知识，最后复核引用。",
                user: String = "",
                hardPolicy: String = AgentConfiguration.defaultHardPolicy) {
        self.soul = soul
        self.agent = agent
        self.user = user
        // The hard policy is an application invariant. Keep the parameter for
        // source compatibility with configuration decoders, but never allow a
        // user-editable document to weaken the tool or safety boundary.
        _ = hardPolicy
        self.hardPolicy = Self.defaultHardPolicy
    }

    public static let defaultHardPolicy = "事实必须来自只读领域工具；不得执行 Shell、任意文件写入或外部副作用；不展示或保存思维链；缺少依据时明确说明。"

    private enum CodingKeys: String, CodingKey { case soul, agent, user }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.soul = try values.decodeIfPresent(String.self, forKey: .soul) ?? ""
        self.agent = try values.decodeIfPresent(String.self, forKey: .agent) ?? ""
        self.user = try values.decodeIfPresent(String.self, forKey: .user) ?? ""
        self.hardPolicy = Self.defaultHardPolicy
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(soul, forKey: .soul); try values.encode(agent, forKey: .agent); try values.encode(user, forKey: .user)
    }
}

public struct AgentPromptContext: Codable, Equatable, Sendable {
    public var hardPolicy: String
    public var soul: String
    public var agent: String
    public var user: String
    public var skill: AgentSkill?
    public var references: [AgentToolResult]
    public var conversation: [AgentMessage]
    public var snapshotID: String

    public init(hardPolicy: String, soul: String, agent: String, user: String, skill: AgentSkill?,
                references: [AgentToolResult] = [], conversation: [AgentMessage] = [], snapshotID: String) {
        self.hardPolicy = hardPolicy
        self.soul = soul
        self.agent = agent
        self.user = user
        self.skill = skill
        self.references = references
        self.conversation = conversation
        self.snapshotID = snapshotID
    }

    /// Render only bounded, user-visible context. Tool payloads remain typed in
    /// the model request and are never copied into trace text as chain of thought.
    public func summary(maxCharacters: Int = 60_000) -> String {
        // Keep the same precedence as the runtime contract: hard policy,
        // current task facts, Skill method, work habits, then persona/user style.
        let policy = "硬策略：\(hardPolicy)"
        var configurationLines: [String] = []
        if let skill { configurationLines.append("Skill：\(skill.title)（\(skill.id)）\n\(skill.instructions)") }
        configurationLines.append("工作习惯：\(agent)")
        configurationLines.append("身份：\(soul)")
        if !user.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { configurationLines.append("用户偏好：\(user)") }
        let configuration = configurationLines.joined(separator: "\n")
        // Reserve room for every editable document so large tool results do
        // not silently remove SOUL/USER from the effective configuration.
        let limit = max(1, maxCharacters)
        let renderedReferences = references.map { reference in
            // Keep the exact citation fields separate from the payload. A
            // display label such as source@revision is ambiguous to a model
            // and can be copied into both fields of a structured claim.
            let envelope = JSONValue.object([
                "sourceRef": .string(reference.sourceRef),
                "sourceRevision": reference.sourceRevision.map(JSONValue.string) ?? .null,
                "evidenceType": .string(reference.evidenceType.rawValue),
                "payload": reference.payload
            ])
            let encoded = (try? String(decoding: AutomationJSON.encode(envelope), as: UTF8.self)) ?? "{}"
            return "依据：\(encoded)"
        }
        let complete = ([policy] + renderedReferences + [configuration]).joined(separator: "\n")
        if complete.count <= limit { return complete }
        guard !renderedReferences.isEmpty else { return String(complete.prefix(limit)) }

        func omissionNotice(_ count: Int, compact: Bool) -> String {
            compact ? "省略 \(count) 项依据。" : "有 \(count) 项依据超过提示长度上限；其内容未提供，请勿据此补造事实。"
        }
        // Reserve the longest possible count before selecting whole payloads.
        // Otherwise a fitting payload can consume the room needed to tell the
        // model that another source was omitted.
        var compactNotice = false
        var reservedNotice = omissionNotice(renderedReferences.count, compact: false)
        if policy.count + reservedNotice.count + 1 > limit {
            compactNotice = true
            reservedNotice = omissionNotice(renderedReferences.count, compact: true)
        }
        guard policy.count + reservedNotice.count + 1 <= limit else {
            // An unusually small caller budget may not fit even the policy
            // and a short notice. Retain policy text and no partial payload.
            return String(policy.prefix(limit))
        }
        let configurationBudget = max(0, limit - policy.count - reservedNotice.count - 2)
        let retainedConfiguration = String(configuration.prefix(configurationBudget))
        var referenceBudget = limit - policy.count - reservedNotice.count - 1
        if !retainedConfiguration.isEmpty { referenceBudget -= retainedConfiguration.count + 1 }
        var lines = [policy]
        for rendered in renderedReferences {
            // Omit a whole payload instead of sending broken JSON as evidence.
            guard rendered.count + 1 <= referenceBudget else { continue }
            lines.append(rendered)
            referenceBudget -= rendered.count + 1
        }
        let omitted = renderedReferences.count - (lines.count - 1)
        lines.append(omissionNotice(omitted, compact: compactNotice))
        if !retainedConfiguration.isEmpty { lines.append(retainedConfiguration) }
        return lines.joined(separator: "\n")
    }
}

public struct PromptContextBuilder: Sendable {
    public let configuration: AgentConfiguration
    public init(configuration: AgentConfiguration = .init()) { self.configuration = configuration }

    /// A new value is created for every run, so edits to configuration cannot
    /// change an in-flight task.
    public func build(skill: AgentSkill?, references: [AgentToolResult] = [], conversation: [AgentMessage] = [],
                      snapshotID: String = UUID().uuidString) -> AgentPromptContext {
        AgentPromptContext(hardPolicy: configuration.hardPolicy, soul: configuration.soul,
                           agent: configuration.agent, user: configuration.user, skill: skill,
                           references: references, conversation: conversation, snapshotID: snapshotID)
    }
}
