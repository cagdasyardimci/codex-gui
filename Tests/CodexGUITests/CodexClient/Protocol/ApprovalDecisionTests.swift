import Testing

@testable import CodexGUI

@Suite
struct ApprovalDecisionTests
{
	@Test func networkPolicyWireValuePreservesHostActionAndLiteralKeys() throws
	{
		let payload: [String: Any] = [
			"applyNetworkPolicyAmendment": [
				"network_policy_amendment": ["host": "example.com", "action": "deny"]
			]
		]
		let decision = try #require(ApprovalDecision(json: payload))
		#expect(decision == .applyNetworkPolicyAmendment(
			host: "example.com",
			action: "deny"
		))
		let encoded = decision.wireValue as? [String: [String: [String: String]]]
		#expect(
			encoded?["applyNetworkPolicyAmendment"]?["network_policy_amendment"] == [
				"host": "example.com",
				"action": "deny",
			]
		)
	}
}
