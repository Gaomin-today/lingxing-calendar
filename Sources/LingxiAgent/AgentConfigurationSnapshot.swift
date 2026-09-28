import Foundation

/// A value captured once at the start of a task, also used for local previews.
/// Draft previews construct another value and never update the running task.
public struct AgentConfigurationSnapshot: Equatable, Sendable {
    public let values: [AgentConfigDocument: String]

    public init(values: [AgentConfigDocument: String]) {
        self.values = Dictionary(uniqueKeysWithValues: AgentConfigDocument.allCases.map {
            ($0, values[$0] ?? $0.defaultContent)
        })
    }

    public var configuration: AgentConfiguration {
        AgentConfiguration(soul: values[.soul]!, agent: values[.agent]!, user: values[.user]!)
    }

    public func chatSkill(includeSystemData: Bool) -> AgentSkill {
        AgentSkill(id: "chat-context", title: "聊天解读",
                   description: "读取选中日期与相关安排，再给出有依据的建议。",
                   requiredTools: includeSystemData ? [.dayContext, .eventsContext] : [.dayContext],
                   instructions: [values[.skill]!, "区分应用事实、传统解释、行动建议和不确定性。"].joined(separator: "\n\n"))
    }

    public func promptContext(includeSystemData: Bool, snapshotID: String) -> AgentPromptContext {
        PromptContextBuilder(configuration: configuration)
            .build(skill: chatSkill(includeSystemData: includeSystemData), snapshotID: snapshotID)
    }
}
