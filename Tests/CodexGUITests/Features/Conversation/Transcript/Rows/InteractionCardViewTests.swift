import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct InteractionCardViewTests
{
	@Test func permissionCardShowsRequestedPathsAndDeniesWithEmptyTurnGrant() throws
	{
		let requested: [String: Any] = [
			"fileSystem": [
				"read": ["/private/project/input"],
				"write": ["/private/project/output"]
			],
			"network": ["enabled": true],
		]
		var submitted: InteractionResponse?
		let card = InteractionCardView(
			interaction: makeInteraction(
				kind: .permissionApproval,
				permissions: requested
			)
		)
		{
			submitted = $0
		}

		let labels = textFields(in: card).map(\.stringValue).joined(separator: "\n")
		#expect(labels.contains("/private/project/input"))
		#expect(labels.contains("/private/project/output"))
		#expect(labels.contains("\"enabled\" : true"))
		#expect(buttons(in: card).map(\.title) == ["Allow for Turn", "Allow for Session", "Deny"])

		try #require(buttons(in: card).first(where:
			{
				$0.title == "Deny"
			})).performClick(nil)
		guard case .permissions(
			let granted,
			let scope
		) = submitted
		else
		{
			Issue.record("Permission denial sent the wrong response type")
			return
		}
		#expect(granted.isEmpty)
		#expect(scope == .turn)
	}

	@Test func commandCardUsesOnlyOfferedDecisionsAndShowsRule() throws
	{
		let rule = ApprovalDecision.acceptWithExecpolicyAmendment(["git", "status"])
		var submitted: InteractionResponse?
		let card = InteractionCardView(
			interaction: makeInteraction(
				kind: .commandApproval,
				decisions: [.decline, rule],
				additionalPermissions: ["fileSystem": ["write": ["/private/project/build"]]]
			)
		)
		{
			submitted = $0
		}

		#expect(buttons(in: card).map(\.title) == ["Deny", "Approve and Save Command Rule"])
		let labels = textFields(in: card).map(\.stringValue).joined(separator: "\n")
		#expect(labels.contains("git status"))
		#expect(labels.contains("/private/project/build"))

		try #require(buttons(in: card).last).performClick(nil)
		guard case .approval(let decision) = submitted
		else
		{
			Issue.record("Approval card sent the wrong response type")
			return
		}
		#expect(decision == rule)
	}

	@Test func anExplicitlyEmptyDecisionListOffersNoApprovalButton()
	{
		let card = InteractionCardView(
			interaction: makeInteraction(
				kind: .commandApproval,
				decisions: []
			)
		)
		{
			_ in
		}
		#expect(buttons(in: card).isEmpty)
		#expect(textFields(in: card).contains
		{
			$0.stringValue.contains("no supported decisions")
		})
	}

	@Test func networkPolicyDecisionKeepsItsHostAndAction() throws
	{
		let decision = ApprovalDecision.applyNetworkPolicyAmendment(
			host: "example.com",
			action: "deny"
		)
		let card = InteractionCardView(
			interaction: makeInteraction(
				kind: .commandApproval,
				decisions: [decision]
			)
		)
		{
			_ in
		}
		#expect(buttons(in: card).map(\.title) == ["Deny Network Rule"])
		#expect(textFields(in: card).contains
		{
			$0.stringValue.contains("deny example.com")
		})
	}

	private func makeInteraction(
		kind: InteractionKind,
		permissions: [String: Any]? = nil,
		decisions: [ApprovalDecision]? = nil,
		additionalPermissions: [String: Any]? = nil
	) -> PendingInteraction
	{
		PendingInteraction(
			id: "request-1",
			threadId: "thread-1",
			turnId: "turn-1",
			itemId: "item-1",
			approvalId: nil,
			kind: kind,
			reason: "Needed for this task",
			command: "git status",
			cwd: "/private/project",
			grantRoot: nil,
			networkHost: nil,
			networkProtocol: nil,
			questions: [],
			requestedPermissions: permissions,
			additionalPermissions: additionalPermissions,
			availableDecisions: decisions
		)
	}

	private func buttons(in view: NSView) -> [NSButton]
	{
		view.subviews.flatMap
		{
			child in
			(child as? NSButton).map
			{
				[$0]
			} ?? buttons(in: child)
		}
	}

	private func textFields(in view: NSView) -> [NSTextField]
	{
		view.subviews.flatMap
		{
			child in
			(child as? NSTextField).map
			{
				[$0]
			} ?? textFields(in: child)
		}
	}
}
