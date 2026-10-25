import Foundation
import Testing

@testable import CodexGUI

@Suite @MainActor
struct TurnReferenceReducerTests
{

	@Test func metadataRequestsRequireAValidatedConversationInTheCheckout() async throws
	{
		try await withTurnReferenceTestFixture()
		{
			fixture in
			let state = fixture.state.store
			let threadID = fixture.service.thread.id
			var model = state.model
			model.conversations.content[.thread(threadID)] = ConversationContentModel()
			model.conversations.turnReferenceIndices[threadID] = TurnReferenceIndex()
			model.conversations.threads = [ThreadSummary(json: [
				"id": threadID,
				"cwd": "/tmp/another-checkout"
			])!]
			let result = ConversationReducer.reduce(
				&model,
				.conversations(.turnReferencesRequested(TurnReferenceReadOperation(
					context: state.operationContext(threadID: threadID),
					cursor: nil
				)))
			)
			#expect(result.effects.isEmpty)
			#expect(model.conversations.turnReferenceIndices[threadID]?.pendingRead == nil)
		}
	}

	private func cacheTurn(
		_ index: Int,
		text: String = "Reply"
	) -> CodexTurn
	{
		CodexTurn(json: ["id": "cache-\(index)", "status": "completed", "items": [
			[
				"id": "request",
				"type": "userMessage",
				"content": [["type": "text", "text": "Request"]]
			],
			["id": "reply", "type": "agentMessage", "text": text]
		]])!
	}

}
