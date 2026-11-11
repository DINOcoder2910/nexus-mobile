// TEMPORARY: stands in for the Claude plumbing the "board tools and the Claude switch" thread is building (NexusCore ClaudeTypes.swift,
// Sources/Claude/ClaudeClient.swift, ClaudeModeChip), with the API it agreed, so the tutor builds before that branch lands. Deleted when
// that branch is merged in; nothing here talks to Claude.
import SwiftUI

enum ClaudeMode: String { case plan, api }
enum ClaudeBlock { case text(String); case image(mediaType: String, base64: String) }
struct ClaudeMessage {
    var role: String
    var content: [ClaudeBlock]
    static func user(_ text: String) -> ClaudeMessage { ClaudeMessage(role: "user", content: [.text(text)]) }
    static func assistant(_ text: String) -> ClaudeMessage { ClaudeMessage(role: "assistant", content: [.text(text)]) }
}
struct ClaudeRequest {
    var model: String
    var system: String
    var messages: [ClaudeMessage]
    var maxTokens: Int = 2048
    var effort: String? = nil
    var cacheSystem: Bool = true
    var sessionId: String? = nil
}
struct ClaudeUsage { var inputTokens = 0, outputTokens = 0, cacheCreationInputTokens = 0, cacheReadInputTokens = 0 }
struct ClaudeReply {
    var text: String
    var usage: ClaudeUsage?
    var cost: Double
    var model: String
    var mode: ClaudeMode
    var msToFirstText: Int?
    var stopReason: String?
    var stopped: Bool
    var sessionId: String?
}
struct ClaudeError: Error { var message: String }
final class ClaudeClient {
    static let shared = ClaudeClient()
    func stream(_ req: ClaudeRequest, onText: @escaping (String) -> Void) async throws -> ClaudeReply {
        throw ClaudeError(message: "The Claude connection isn't in this build yet.")
    }
}
struct ClaudeModeChip: View {
    var body: some View { Text("API").font(.caption.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 2).background(.quaternary, in: Capsule()) }
}
