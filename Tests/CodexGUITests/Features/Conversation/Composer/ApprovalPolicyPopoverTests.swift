import AppKit
import Testing

@testable import CodexGUI

@Suite(
	.serialized,
	.testTiming
) @MainActor
struct ApprovalPolicyPopoverTests
{
	@Test func referenceGeometryKeyboardSelectionAndDocumentationLink() throws
	{
		_ = NSApplication.shared
		let controller = ApprovalPolicyPopoverView()
		let window = NSWindow(
			contentRect: NSRect(
				origin: .zero,
				size: controller.preferredContentSize
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		window.appearance = NSAppearance(named: .aqua)
		window.contentViewController = controller
		window.setContentSize(controller.preferredContentSize)
		defer
		{
			window.close()
		}
		controller.render(mode: .fullAccess)
		window.layoutIfNeeded()
		let content = controller.view
		#expect(abs(content.bounds.width - controller.preferredContentSize.width) < 0.51)
		#expect(abs(content.bounds.height - controller.preferredContentSize.height) < 0.51)
		#expect(content.accessibilityRole() == .menu)
		let stack = try #require(content.subviews.first as? NSStackView)
		let header = try #require(stack.arrangedSubviews.first as? NSStackView)
		let rows = stack.arrangedSubviews.compactMap
		{
			$0 as? NSButton
		}
		#expect(header.bounds.height == 26)
		#expect(rows.count == 3)
		for row in rows
		{
			#expect(abs(row.bounds.width - 431.09375) < 0.51)
			#expect(abs(row.bounds.height - 42.5703125) < 0.26)
			#expect(row.accessibilityRole() == .menuItem)
			let sharedRow = try #require(row as? DesktopMenuRow)
			let labels = [sharedRow.titleLabel, sharedRow.subtitleLabel]
			#expect(labels[0].frame.minX == 30)
			#expect(labels[0].alignmentRect(forFrame: labels[0].frame).minX == 32)
			#expect(abs(labels[0].bounds.height - 18.5703125) < 0.26)
			#expect(labels[1].bounds.height == 14)
			let images = [sharedRow.iconView, sharedRow.trailingImageView]
			#expect(images[0].frame.minX == 8)
			#expect(images[0].bounds.width == 16)
			#expect(images[1].bounds.width == 16)
			#expect(abs(row.bounds.maxX - images[1].frame.maxX - 8) < 0.01)
		}
		controller.focusSelectedRow()
		#expect(window.firstResponder === rows[2])
		rows[2].keyDown(with: try key(
			126,
			window: window
		))
		#expect(window.firstResponder === rows[1])
		var selected: ApprovalMode?
		controller.onSelect =
		{
			selected = $0
		}
		rows[1].keyDown(with: try key(
			36,
			window: window
		))
		#expect(selected == .approveForMe)
		let link = try #require(header.arrangedSubviews.last as? NSButton)
		#expect(rows[2].nextKeyView === link)
		var opened: URL?
		controller.openDocumentation =
		{
			opened = $0
		}
		let actionTiming = TestTiming.begin(
			"popover.action",
			detail: "documentation"
		)
		// This assertion concerns the configured link action rather than native press tracking.
		try #require(link.dispatchConfiguredAction())
		actionTiming.end()
		#expect(opened == DocumentationLinks.sandboxing)
		if let path = ProcessInfo.processInfo.environment["CODEX_GUI_APPROVAL_CAPTURE"]
		{
			try AppTestPNGWriter.write(
				content,
				to: URL(fileURLWithPath: path)
			)
		}
	}

	// Presents a key approval panel with application event monitors, then restores its host.
	@Test func panelAlignsAboveTriggerAndTogglesWithoutNativeArrow() async throws
	{
		let timing = TestTiming.begin("test.body")
		defer
		{
			timing.end()
		}
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let controller = ConversationViewController()
			let window = NSWindow(
				contentRect: NSRect(
					x: 100,
					y: 100,
					width: 1000,
					height: 700
				),
				styleMask: [.borderless],
				backing: .buffered,
				defer: false
			)
			window.prepareForTesting()
			window.contentViewController = controller
			window.setContentSize(NSSize(
				width: 1000,
				height: 700
			))
			window.layoutIfNeeded()
			controller.showApprovalPolicy()
			let popover = try #require(controller.approvalPolicyPopover)
			let panel = try #require(controller.approvalPolicyController.view.window)
			defer
			{
				popover.close(); window.close()
			}
			#expect(popover.isShown)
			let anchor = window.convertToScreen(controller.approvalPolicyButton.convert(
				controller.approvalPolicyButton.bounds,
				to: nil
			))
			#expect(abs(panel.frame.minX - anchor.minX - 1) < 0.51)
			#expect(abs(panel.frame.minY - anchor.maxY - 1.7890625) < 0.51)
			#expect(abs(panel.frame.width - 439.09375) < 0.51)
			#expect(abs(panel.frame.height - 161.7109375) < 0.51)
			controller.showApprovalPolicy()
			#expect(!popover.isShown)
			controller.showApprovalPolicy()
			#expect(popover.isShown)
			NotificationCenter.default.post(
				name: NSWindow.willMiniaturizeNotification,
				object: window
			)
			window.performMiniaturize(nil)
			NotificationCenter.default.post(
				name: NSWindow.didResignMainNotification,
				object: window
			)
			NotificationCenter.default.post(
				name: NSApplication.didResignActiveNotification,
				object: NSApp
			)
			NotificationCenter.default.post(
				name: NSWindow.didMiniaturizeNotification,
				object: window
			)
			#expect(popover.isShown)
			window.deminiaturize(nil)
			NotificationCenter.default.post(
				name: NSWindow.didDeminiaturizeNotification,
				object: window
			)
			#expect(popover.isShown)
			#expect(window.childWindows?.contains(panel) == true)
			#expect(abs(panel.frame.minX - anchor.minX - 1) < 0.51)
			NotificationCenter.default.post(
				name: NSApplication.didResignActiveNotification,
				object: NSApp
			)
			#expect(!popover.isShown)
		}
	}

	@Test func hoveringAnotherApprovalRowClearsPreviousHoverAndKeepsSelection() throws
	{
		_ = NSApplication.shared
		let controller = ApprovalPolicyPopoverView()
		controller.view.appearance = NSAppearance(named: .darkAqua)
		controller.render(mode: .fullAccess)
		let stack = try #require(controller.view.subviews.first as? NSStackView)
		let rows = stack.arrangedSubviews.compactMap
		{
			$0 as? DesktopMenuRow
		}
		try #require(rows.count == 3)
		let event = try #require(NSEvent.mouseEvent(
			with: .mouseMoved,
			location: .zero,
			modifierFlags: [],
			timestamp: 0,
			windowNumber: 0,
			context: nil,
			eventNumber: 0,
			clickCount: 0,
			pressure: 0
		))
		rows[0].mouseEntered(with: event)
		#expect(rows[0].isHovered)
		#expect(rows[0].subviews.compactMap
		{
			$0 as? NSImageView
		}.allSatisfy
		{
			$0.alphaValue == 1
		})
		rows[1].mouseEntered(with: event)
		#expect(!rows[0].isHovered && rows[1].isHovered)
		#expect(rows[0].subviews.compactMap
		{
			$0 as? NSImageView
		}.allSatisfy
		{
			$0.alphaValue == 0.75
		})
		controller.clearHover()
		#expect(rows.allSatisfy
		{
			!$0.isHovered
		})
		#expect(rows[2].accessibilityValue() as? String == "Selected")
	}

	private func key(
		_ code: UInt16,
		window: NSWindow
	) throws -> NSEvent
	{
		try #require(NSEvent.keyEvent(
			with: .keyDown,
			location: .zero,
			modifierFlags: [],
			timestamp: 0,
			windowNumber: window.windowNumber,
			context: nil,
			characters: "",
			charactersIgnoringModifiers: "",
			isARepeat: false,
			keyCode: code
		))
	}
}
