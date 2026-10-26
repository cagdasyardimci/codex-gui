import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct DesktopStyledButtonTests
{
	@Test func regularActionsOwnDialogGeometryAndDestructiveSemantics() throws
	{
		_ = NSApplication.shared
		let cancel = DesktopStyledButton(
			title: "Cancel",
			presentation: .secondary,
			size: .regular
		)
		let delete = DesktopStyledButton(
			title: "Delete",
			presentation: .destructive,
			size: .regular
		)
		let save = DesktopStyledButton(
			title: "Save",
			presentation: .primary,
			size: .regular
		)
		for button in [cancel, delete, save]
		{
			#expect(button.intrinsicContentSize.height == 32)
			#expect(button.intrinsicContentSize.width >= 78)
			#expect(button.font?.pointSize == 14)
		}
		#expect(delete.hasDestructiveAction)
		#expect(!cancel.hasDestructiveAction && !save.hasDestructiveAction)
		let oldWidth = cancel.intrinsicContentSize.width
		cancel.title = "Cancel this pending operation"
		#expect(cancel.intrinsicContentSize.width > oldWidth)
	}

	@Test func loadingOwnsItsIndicatorWithoutReplacingNativeActionOrLabel() throws
	{
		_ = NSApplication.shared
		var actions = 0
		let button = DesktopActionButton(
			title: "Add",
			presentation: .primary
		)
		{
			actions += 1
		}
		let originalWidth = button.intrinsicContentSize.width
		let target = button.target
		let action = button.action
		button.isEnabled = false
		button.isLoading = true
		let indicator = try #require(button.subviews.compactMap
		{
			$0 as? NSProgressIndicator
		}
		.first)
		#expect(!indicator.isHidden)
		#expect(button.intrinsicContentSize.width == originalWidth + 16)
		#expect(!button.dispatchConfiguredAction())
		#expect(actions == 0)
		#expect(button.title == "Add" && button.accessibilityLabel() == "Add")
		button.isLoading = false
		button.isEnabled = true
		#expect(indicator.isHidden)
		#expect(button.intrinsicContentSize.width == originalWidth)
		#expect(button.target === target && button.action == action)
		#expect(button.dispatchConfiguredAction())
		#expect(actions == 1)
	}

	@Test(.appKitIsolation)
	func semanticStatesDrawDistinctlyAcrossAppearancesAndRetainKeyboardFocus() throws
	{
		_ = NSApplication.shared
		let button = DesktopStyledButton(
			title: "Delete",
			presentation: .destructive,
			size: .regular
		)
		button.frame = NSRect(
			x: 20,
			y: 20,
			width: 92,
			height: 32
		)
		let window = NSWindow(
			contentRect: NSRect(
				x: -2000,
				y: -2000,
				width: 160,
				height: 80
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		window.contentView?.addSubview(button)
		defer
		{
			window.close()
		}
		#expect(window.makeFirstResponder(button))
		let event = try #require(NSEvent.mouseEvent(
			with: .mouseMoved,
			location: .zero,
			modifierFlags: [],
			timestamp: 0,
			windowNumber: window.windowNumber,
			context: nil,
			eventNumber: 0,
			clickCount: 0,
			pressure: 0
		))
		var images: [Data] = []
		for name in [NSAppearance.Name.aqua, .darkAqua, .aqua]
		{
			window.appearance = try #require(NSAppearance(named: name))
			button.isEnabled = true
			button.mouseExited(with: event)
			let idle = try image(button)
			button.mouseEntered(with: event)
			#expect(try image(button) != idle)
			#expect(window.firstResponder === button)
			button.isEnabled = false
			#expect(try image(button) != idle)
			button.isEnabled = true
			#expect(window.makeFirstResponder(button))
			button.mouseExited(with: event)
			images.append(try image(button))
			#expect(window.firstResponder === button)
			#expect(button.frame.size == NSSize(
				width: 92,
				height: 32
			))
		}
		#expect(images[0] != images[1])
		#expect(images[0] == images[2])
	}

	private func image(_ view: NSView) throws -> Data
	{
		let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
		view.cacheDisplay(
			in: view.bounds,
			to: bitmap
		)
		return try #require(bitmap.representation(
			using: .png,
			properties: [:]
		))
	}
}
