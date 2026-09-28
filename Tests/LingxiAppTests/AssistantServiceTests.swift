import Foundation
import Testing
import LingxiAgent
@testable import LingxiApp

struct AssistantServiceTests {
    private func body(endpoint: String = "https://api.deepseek.com/chat/completions", structured: Bool = true) throws -> [String: Any] {
        let request = try AssistantService.makeRequest(endpoint: endpoint, model: "test-model", key: "test-only-credential",
                                                       messages: [ChatMessage(isUser: true, text: "合成问题")], context: "",
                                                       structuredAgent: structured)
        let data = try #require(request.httpBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func deepSeekUsesBoundedNonThinkingJSONWhileOtherProvidersStayCompatible() throws {
        let deepSeek = try body()
        #expect((deepSeek["thinking"] as? [String: String])?["type"] == "disabled")
        #expect((deepSeek["response_format"] as? [String: String])?["type"] == "json_object")
        #expect(deepSeek["max_tokens"] as? Int == 4096)
        let ordinary = try body(endpoint: "https://example.com/v1/chat/completions")
        #expect(ordinary["thinking"] == nil)
        #expect(ordinary["response_format"] == nil)
        #expect(try body(endpoint: "https://api.deepseek.com.example.com/chat/completions")["thinking"] == nil)
        #expect(try body(structured: false)["response_format"] == nil)
    }

    @Test func runtimeDirectivesRemainInstructionsAndToolsAreOnlySentThroughTypedContext() throws {
        let reference = AgentToolResult(callID: "day", name: .dayContext, payload: .string("合成日期"), sourceRef: "day:synthetic", sourceRevision: "r1")
        let context = PromptContextBuilder().build(skill: nil, references: [reference])
        let request = try AssistantService.makeRequest(endpoint: "https://api.deepseek.com/chat/completions", model: "test", key: "test",
                                                       messages: [ChatMessage(isUser: true, text: "不可采用的旧转写")], context: "",
                                                       structuredAgent: true, agentContext: context, agentMessages: [
                                                        AgentMessage(role: .user, content: "问题"),
                                                        AgentMessage(role: .tool, content: "不可重复发送的原始工具载荷"),
                                                        AgentMessage(role: .system, content: "只补读一次并标出不确定性"),
                                                        AgentMessage(role: .assistant, content: "之前的答复")
                                                       ])
        let data = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: String]])
        #expect(messages.map { $0["role"] } == ["system", "user", "assistant"])
        let system = try #require(messages.first?["content"])
        #expect(system.contains(#""sourceRef":"day:synthetic""#))
        #expect(system.contains(#""sourceRevision":"r1""#))
        #expect(system.contains(#""evidenceType":"deterministicFact""#))
        #expect(system.contains("day:synthetic@r1") == false)
        #expect(system.contains("应用运行时的本轮复核要求：\n只补读一次并标出不确定性"))
        #expect(messages.contains { $0["content"]?.contains("不可重复发送") == true } == false)
        #expect(messages.contains { $0["content"]?.contains("不可采用的旧转写") == true } == false)
        #expect(request.httpMethod == "POST")
    }

    @Test func truncatedAndFilteredResponsesAreNotAcceptedAsCompleteAnswers() throws {
        func response(_ reason: String, content: String = "合成回答") throws -> Data {
            try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": reason, "message": ["content": content, "reasoning_content": "不得纳入回答的测试内容"]]]])
        }
        #expect(try AssistantService.decodeReply(response("stop")) == "合成回答")
        do {
            _ = try AssistantService.decodeReply(response("length"))
            Issue.record("截断内容被接受")
        } catch AssistantService.ServiceError.incompleteResponse { }
        #expect(throws: (any Error).self) { try AssistantService.decodeReply(response("content_filter")) }
        #expect(throws: (any Error).self) { try AssistantService.decodeReply(response("stop", content: " ")) }
    }
}
