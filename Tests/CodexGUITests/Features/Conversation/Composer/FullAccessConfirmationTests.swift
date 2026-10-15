import AppKit
import Testing

@testable import CodexGUI

@Suite(
	.serialized,
	.testTiming
) @MainActor
struct FullAccessConfirmationTests
{
	// Real AppKit sheet presentation and asynchronous dismissal share application focus.
	@Test func fullAccessWaitsForConfirmationAndKeepsTheRequestingWorkspace(
	) async throws
	{
		let timing = TestTiming.begin("test.body")
		defer
		{
			timing.end()
		}
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			// Reserve shared focus only after the test body has reached MainActor.
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
				if let sheet = window.attachedSheet
				{
					window.endSheet(
						sheet,
						returnCode: .cancel
					)
				}
				window.close()
			}
			var firstWorkspace: [ApprovalMode] = []
			var secondWorkspace: [ApprovalMode] = []
			conversation.onSelectApprovalMode =
			{
				firstWorkspace.append($0)
			}
			conversation.requestApprovalMode(.fullAccess)
			let panel = try #require(conversation
				.fullAccessConfirmationPanel as? FullAccessConfirmationPanel)
			let dialog = try #require(panel.contentViewController as? FullAccessConfirmationView)
			#expect(firstWorkspace.isEmpty)
			#expect(conversation.approvalMode == .askForApproval)
			#expect(panel.canBecomeKey)
			let cancelAction = TestTiming.begin(
				"sheet.action",
				detail: "cancel"
			)
			// Verify configured action routing without the native press-tracking event loop.
			try #require(dialog.cancelButton.dispatchConfiguredAction())
			cancelAction.end()
			let cancelDismissal = TestTiming.begin(
				"sheet.dismissal",
				detail: "cancel"
			)
			try await panel.waitForDismissal()
			cancelDismissal.end()
			#expect(conversation.fullAccessConfirmationPanel == nil)
			#expect(firstWorkspace.isEmpty)

			conversation.requestApprovalMode(.fullAccess)
			let escapedPanel = try #require(
				conversation.fullAccessConfirmationPanel as? FullAccessConfirmationPanel
			)
			let escapeAction = TestTiming.begin(
				"sheet.action",
				detail: "escape"
			)
			escapedPanel.cancelOperation(nil)
			escapeAction.end()
			let escapeDismissal = TestTiming.begin(
				"sheet.dismissal",
				detail: "escape"
			)
			try await escapedPanel.waitForDismissal()
			escapeDismissal.end()
			#expect(conversation.fullAccessConfirmationPanel == nil)
			#expect(firstWorkspace.isEmpty)

			conversation.requestApprovalMode(.fullAccess)
			let confirmedPanel = try #require(
				conversation.fullAccessConfirmationPanel as? FullAccessConfirmationPanel
			)
			let confirmedDialog = try #require(
				confirmedPanel.contentViewController as? FullAccessConfirmationView
			)
			conversation.onSelectApprovalMode =
			{
				secondWorkspace.append($0)
			}
			let confirmAction = TestTiming.begin(
				"sheet.action",
				detail: "confirm"
			)
			try #require(confirmedDialog.confirmButton.dispatchConfiguredAction())
			confirmAction.end()
			let confirmDismissal = TestTiming.begin(
				"sheet.dismissal",
				detail: "confirm"
			)
			try await confirmedPanel.waitForDismissal()
			confirmDismissal.end()
			#expect(conversation.fullAccessConfirmationPanel == nil)
			#expect(firstWorkspace == [.fullAccess])
			#expect(secondWorkspace.isEmpty)
			conversation.requestApprovalMode(.approveForMe)
			#expect(secondWorkspace == [.approveForMe])
			#expect(conversation.fullAccessConfirmationPanel == nil)
		}
	}

	@Test(
		.timeLimit(.minutes(1)),
		arguments: [UInt16(36), 76, 53]
	)
	func dialogKeysDismissThroughNativeEventRouting(keyCode: UInt16) async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
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
				if let sheet = window.attachedSheet
				{
					window.endSheet(
						sheet,
						returnCode: .cancel
					)
				}
				window.close()
			}
			var requestingWorkspace: [ApprovalMode] = []
			var replacementWorkspace: [ApprovalMode] = []
			conversation.onSelectApprovalMode =
			{
				requestingWorkspace.append($0)
			}
			conversation.requestApprovalMode(.fullAccess)
			let panel = try #require(
				conversation.fullAccessConfirmationPanel as? FullAccessConfirmationPanel
			)
			conversation.onSelectApprovalMode =
			{
				replacementWorkspace.append($0)
			}
			let characters = keyCode == 53 ? "\u{1b}" : keyCode == 76 ? "\u{3}" : "\r"
			let event = try #require(NSEvent.keyEvent(
				with: .keyDown,
				location: .zero,
				modifierFlags: [],
				timestamp: 0,
				windowNumber: panel.windowNumber,
				context: nil,
				characters: characters,
				charactersIgnoringModifiers: characters,
				isARepeat: false,
				keyCode: keyCode
			))
			panel.sendEvent(event)
			try await panel.waitForDismissal()
			#expect(window.attachedSheet == nil)
			#expect(conversation.fullAccessConfirmationPanel == nil)
			#expect(requestingWorkspace == (keyCode == 53 ? [] : [.fullAccess]))
			#expect(replacementWorkspace.isEmpty)
		}
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
