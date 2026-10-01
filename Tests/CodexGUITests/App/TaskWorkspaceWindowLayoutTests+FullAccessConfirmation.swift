import AppKit
import Testing

@testable import CodexGUI

@MainActor
extension TaskWorkspaceWindowLayoutTests
{
	@Test func fullAccessWaitsForConfirmationAndKeepsTheRequestingWorkspace() async throws
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
		window.isReleasedWhenClosed = false
		window.contentViewController = conversation
		window.orderFront(nil)
		defer
		{
			window.close()
		}
		var firstWorkspace: [ApprovalMode] = []
		var secondWorkspace: [ApprovalMode] = []
		conversation.onSelectApprovalMode =
		{
			firstWorkspace.append($0)
		}
		conversation.requestApprovalMode(.fullAccess)
		let panel = try #require(conversation.fullAccessConfirmationPanel)
		let dialog = try #require(panel.contentViewController as? FullAccessConfirmationView)
		#expect(firstWorkspace.isEmpty)
		#expect(conversation.approvalMode == .askForApproval)
		#expect(panel.canBecomeKey)
		dialog.cancelButton.performClick(nil)
		await waitForConfirmationDismissal(conversation)
		#expect(conversation.fullAccessConfirmationPanel == nil)
		#expect(firstWorkspace.isEmpty)

		conversation.requestApprovalMode(.fullAccess)
		let escapedPanel = try #require(conversation.fullAccessConfirmationPanel)
		escapedPanel.cancelOperation(nil)
		await waitForConfirmationDismissal(conversation)
		#expect(conversation.fullAccessConfirmationPanel == nil)
		#expect(firstWorkspace.isEmpty)

		conversation.requestApprovalMode(.fullAccess)
		let confirmedPanel = try #require(conversation.fullAccessConfirmationPanel)
		let confirmedDialog = try #require(
			confirmedPanel.contentViewController as? FullAccessConfirmationView
		)
		conversation.onSelectApprovalMode =
		{
			secondWorkspace.append($0)
		}
		confirmedDialog.confirmButton.performClick(nil)
		await waitForConfirmationDismissal(conversation)
		#expect(conversation.fullAccessConfirmationPanel == nil)
		#expect(firstWorkspace == [.fullAccess])
		#expect(secondWorkspace.isEmpty)
		conversation.requestApprovalMode(.approveForMe)
		#expect(secondWorkspace == [.approveForMe])
		#expect(conversation.fullAccessConfirmationPanel == nil)
	}

	@Test func fullAccessDialogHasWorkingLinkKeyboardActionsAndUnclippedContent() throws
	{
		_ = NSApplication.shared
		let dialog = FullAccessConfirmationView()
		_ = dialog.view
		dialog.view.frame.size = dialog.view.fittingSize
		dialog.view.layoutSubtreeIfNeeded()
		#expect(dialog.cancelButton.keyEquivalent == "\u{1b}")
		#expect(dialog.confirmButton.keyEquivalent == "\r")
		let text = try #require(dialog.riskText.textStorage)
		let link = text.attribute(
			.link,
			at: text.length - 1,
			effectiveRange: nil
		) as? URL
		#expect(link == DocumentationLinks.sandboxing)
		let layout = try #require(dialog.riskText.layoutManager)
		let container = try #require(dialog.riskText.textContainer)
		layout.ensureLayout(for: container)
		#expect(layout.usedRect(for: container).height <= dialog.riskText.bounds.height)
		#expect(dialog.view.fittingSize.width == 518)
		verifyLabelsFit(
			in: dialog.view,
			root: dialog.view
		)
		if let directory = ProcessInfo.processInfo.environment["CODEX_GUI_UI_EVIDENCE_DIRECTORY"]
		{
			let output = URL(fileURLWithPath: directory)
			try FileManager.default.createDirectory(
				at: output,
				withIntermediateDirectories: true
			)
			for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)]
			{
				dialog.view.appearance = NSAppearance(named: appearance)
				let bitmap = try #require(dialog.view
					.bitmapImageRepForCachingDisplay(in: dialog.view.bounds))
				dialog.view.cacheDisplay(
					in: dialog.view.bounds,
					to: bitmap
				)
				let png = try #require(bitmap.representation(
					using: .png,
					properties: [:]
				))
				try png.write(to: output.appendingPathComponent("full-access-\(name).png"))
			}
		}
	}

	private func waitForConfirmationDismissal(_ conversation: ConversationViewController) async
	{
		for _ in 0 ..< 100
		{
			if conversation.fullAccessConfirmationPanel == nil
			{
				return
			}
			try? await Task.sleep(for: .milliseconds(10))
		}
	}

	private func verifyLabelsFit(
		in view: NSView,
		root: NSView
	)
	{
		if view is NSTextField
		{
			let frame = view.convert(
				view.bounds,
				to: root
			)
			#expect(root.bounds.insetBy(
				dx: -1,
				dy: -1
			).contains(frame))
		}
		for child in view.subviews
		{
			verifyLabelsFit(
				in: child,
				root: root
			)
		}
	}
}
