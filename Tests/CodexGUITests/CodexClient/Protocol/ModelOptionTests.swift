import Foundation
import Testing

@testable import CodexGUI

struct ModelOptionTests
{
	@Test func modelFixtureUsesBackendModelIdentifierAndEfforts() throws
	{
		let model = try #require(
			ModelOption(json: [
				"id": "catalog-row-id",
				"model": "gpt-6-sol",
				"displayName": "GPT-6 Sol",
				"supportedReasoningEfforts": [
					["reasoningEffort": "low", "description": "Faster"],
					["reasoningEffort": "high", "description": "Deeper"],
				],
				"defaultReasoningEffort": "high",
				"isDefault": true,
			])
		)

		#expect(model.id == "gpt-6-sol")
		#expect(model.supportedReasoningEfforts == ["low", "high"])
		#expect(model.defaultReasoningEffort == "high")
	}

}
