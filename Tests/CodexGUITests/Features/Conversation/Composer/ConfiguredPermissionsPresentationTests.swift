import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct ConfiguredPermissionsPresentationTests
{
	@Test func configuredPermissionsReplacePresetLabelAndSelection() throws
	{
		_ = NSApplication.shared
		let conversation = ConversationViewController()
		_ = conversation.view
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: nil
		))
		model.preferences.runPreferences = RunPreferences(
			approvalMode: .fullAccess,
			fastMode: false,
			configurationDefaults: RunConfigurationDefaults(
				approvalPolicy: .onRequest,
				sandboxMode: .readOnly
			)
		)
		let snapshot = WorkspaceSelectors(
			model: model,
			now: Date()
		).makeSnapshot()
		#expect(snapshot.configurationDefaults == model.preferences.runPreferences
			.configurationDefaults)
		conversation
			.renderModelAndApprovalPreferences(ConversationPresentation(snapshot).preferences)
		#expect(conversation.approvalPolicyButton.title == "Configured permissions")
		#expect(conversation.approvalPolicyButton.toolTip?.contains("Read-only files") == true)
		#expect(conversation.approvalPolicyButton.toolTip?.contains("on request") == true)
		let policy = conversation.approvalPolicyController
		_ = policy.view
		let rows = descendants(policy.view).compactMap
		{
			$0 as? NSButton
		}
		.filter
		{
			$0.accessibilityRole() == .menuItem
		}
		#expect(rows.count == 3)
		#expect(rows.allSatisfy
		{
			$0.accessibilityValue() as? String == "Not selected"
		})
	}

	@Test(.appKitIsolation)
	func selectingFullAccessFromConfiguredReadOnlyStillRequiresConfirmation() async throws
	{
		_ = NSApplication.shared
		let conversation = ConversationViewController()
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 900,
				height: 700
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		window.contentViewController = conversation
		window.orderFront(nil)
		defer
		{
			if let sheet = window.attachedSheet
			{
				window.endSheet(
					sheet,
					returnCode: .cancel
				)
			}
			window.close()
		}
		conversation.approvalMode = .fullAccess
		conversation.hasConfiguredPermissions = true
		var applied = false
		conversation.onSelectApprovalMode =
		{
			_ in applied = true
		}
		conversation.requestApprovalMode(.fullAccess)
		let panel = try #require(conversation
			.fullAccessConfirmationPanel as? FullAccessConfirmationPanel)
		#expect(!applied)
		panel.cancelOperation(nil)
		try await panel.waitForDismissal()
		#expect(!applied)
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		view.subviews.flatMap
		{
			[$0] + descendants($0)
		}
	}
}
