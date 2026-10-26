import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct AccountMenuPanelTests
{

	@Test func accountSuffixesRemainReadableAfterPresentation() async throws
	{
		try await AppKitTestIsolation.perform
		{
			_ = NSApplication.shared
			let parent = NSWindow(
				contentRect: NSRect(
					x: 100,
					y: 100,
					width: 600,
					height: 400
				),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			parent.prepareForTesting()
			let anchor = NSButton(frame: NSRect(
				x: 12,
				y: 12,
				width: 30,
				height: 30
			))
			parent.contentView?.addSubview(anchor)
			parent.makeKeyAndOrderFront(nil)
			let content = StatusPopoverView(frame: .zero)
			let usage = try #require(content.menuButtons[0] as? DesktopMenuRow)
			let settings = try #require(content.menuButtons[1] as? DesktopMenuRow)
			usage.suffix = "Unavailable"
			#expect(usage.accessibilityValue() as? String == "Unavailable")
			usage.suffix = "88% left · stale"
			#expect(usage.accessibilityValue() as? String == "88% left · stale")
			usage.suffix = ""
			#expect(usage.accessibilityValue() == nil)
			usage.suffix = "Unavailable"
			#expect(settings.accessibilityValue() == nil)
			let menu = AccountMenuPanel(content: content)
			defer
			{
				menu.close(); parent.close()
			}
			menu.show(from: anchor)
			let panel = try #require(content.window)
			panel.contentView?.layoutSubtreeIfNeeded()
			panel.displayIfNeeded()
			for row in [usage, settings]
			{
				let label = row.suffixLabel
				let cell = try #require(label.cell)
				#expect(label.frame.width >= ceil(cell.cellSize.width))
				#expect(row.titleLabel.frame.maxX < label.frame.minX)
			}
		}
	}

	@Test func menuSurvivesParentMiniaturizationAndStillDismissesOnFocusLoss() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let window = NSWindow(
				contentRect: NSRect(
					x: 100,
					y: 100,
					width: 600,
					height: 400
				),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			window.prepareForTesting()
			let trigger = NSButton(frame: NSRect(
				x: 12,
				y: 12,
				width: 30,
				height: 30
			))
			window.contentView?.addSubview(trigger)
			window.makeKeyAndOrderFront(nil)
			let menu = AccountMenuPanel(content: StatusPopoverView(frame: .zero))
			defer
			{
				menu.close()
				window.close()
			}
			menu.show(from: trigger)
			let panel = try #require(menu.content.window)
			let center = NotificationCenter.default
			center.post(
				name: NSWindow.willMiniaturizeNotification,
				object: window
			)
			center.post(
				name: NSWindow.didResignMainNotification,
				object: window
			)
			center.post(
				name: NSWindow.didMiniaturizeNotification,
				object: window
			)
			#expect(menu.isShown)
			center.post(
				name: NSWindow.didDeminiaturizeNotification,
				object: window
			)
			#expect(menu.isShown)
			#expect(panel.isVisible)
			center.post(
				name: NSWindow.didResignMainNotification,
				object: window
			)
			#expect(!menu.isShown)
			#expect(!panel.isVisible)
		}
	}

	@Test func menuKeyboardSkipsDisabledActionsAndEscapeDismisses() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let window = NSWindow(
				contentRect: NSRect(
					x: 100,
					y: 100,
					width: 600,
					height: 400
				),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			window.prepareForTesting()
			let trigger = NSButton(frame: NSRect(
				x: 12,
				y: 12,
				width: 30,
				height: 30
			))
			window.contentView?.addSubview(trigger)
			window.makeKeyAndOrderFront(nil)
			let content = StatusPopoverView(frame: .zero)
			let menu = AccountMenuPanel(content: content)
			defer
			{
				menu.close(); window.close()
			}
			content.menuButtons[2].isEnabled = false
			var usageInvocations = 0
			var settingsInvocations = 0
			content.onShowUsage =
			{
				usageInvocations += 1
			}
			content.onShowSettings =
			{
				settingsInvocations += 1
			}
			menu.show(from: trigger)
			let panel = try #require(content.window)
			panel.contentView?.layoutSubtreeIfNeeded()
			// Native stack layout rounds fractional CSS metrics to the backing pixel grid.
			let tolerance = 0.5 / (panel.screen?.backingScaleFactor ?? 1)
			#expect(content.frame.width == LayoutTokens.AccountMenu.width
				- 2 * LayoutTokens.AccountMenu.gutter)
			#expect(abs(content.frame.height + 2 * LayoutTokens.AccountMenu.gutter
					- LayoutTokens.AccountMenu.height) <= tolerance)
			let settings = content.menuButtons[1]
			#expect(abs(settings.frame.height - LayoutTokens.AccountMenu.rowHeight) <= tolerance)
			let hit = settings.hitTest(NSPoint(
				x: settings.frame.midX,
				y: settings.frame.midY
			))
			#expect(hit === settings)
			@MainActor func key(_ keyCode: UInt16) throws
			{
				let event = try #require(NSEvent.keyEvent(
					with: .keyDown,
					location: .zero,
					modifierFlags: [],
					timestamp: 0,
					windowNumber: panel.windowNumber,
					context: nil,
					characters: "",
					charactersIgnoringModifiers: "",
					isARepeat: false,
					keyCode: keyCode
				))
				#expect(!menu.shouldForward(event))
			}
			try key(125)
			#expect(panel.firstResponder === content.menuButtons[0])
			try key(36)
			#expect(usageInvocations == 1)
			try key(125)
			#expect(panel.firstResponder === settings)
			try key(36)
			#expect(settingsInvocations == 1)
			try key(125)
			#expect(panel.firstResponder === content.menuButtons[0])
			try key(53)
			#expect(!menu.isShown)
			#expect(!panel.isVisible)
		}
	}
}
