import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct ConversationLockViewTests
{
	@Test(.appKitIsolation)
	func retainedActionsKeepHoverFocusAndDisabledAppearanceAcrossWindowChanges() throws
	{
		_ = NSApplication.shared
		let lock = ConversationLockView()
		let window = NSWindow(
			contentRect: NSRect(
				x: -2000,
				y: -2000,
				width: 640,
				height: 80
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		window.contentView = lock
		defer
		{
			window.close()
		}
		window.layoutIfNeeded()
		let retry = try #require(lock.subviews.compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.title == "Retry"
		})
		let fork = try #require(lock.subviews.compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.title == "Fork chat"
		})
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
		let styledRetry = try #require(retry as? DesktopStyledButton)
		#expect(styledRetry.presentation == .quiet)
		let cell = retry.cell
		let frame = retry.frame
		var retries = 0
		lock.onRetry =
		{
			retries += 1
		}
		#expect(window.makeFirstResponder(retry))
		retry.mouseEntered(with: event)
		var enabledImages: [Data] = []
		for appearance in [NSAppearance.Name.aqua, .darkAqua, .aqua]
		{
			window.appearance = try #require(NSAppearance(named: appearance))
			window.displayIfNeeded()
			enabledImages.append(try renderedImage(retry))
			#expect(styledRetry.isHovered)
			#expect(retry.frame == frame && retry.cell === cell)
			#expect(window.firstResponder === retry)
		}
		#expect(enabledImages[0] != enabledImages[1])
		#expect(enabledImages[0] == enabledImages[2])
		lock.isRetrying = true
		for appearance in [NSAppearance.Name.darkAqua, .aqua]
		{
			window.appearance = try #require(NSAppearance(named: appearance))
			window.displayIfNeeded()
			#expect(try renderedImage(retry) != enabledImages[appearance == .aqua ? 0 : 1])
			#expect(!retry.isEnabled)
			#expect(!retry.dispatchConfiguredAction())
		}
		#expect(!fork.isEnabled && !fork.dispatchConfiguredAction())
		#expect(retries == 0)
		lock.isRetrying = false
		#expect(retry.dispatchConfiguredAction())
		#expect(retries == 1)
		retry.mouseExited(with: event)
		#expect(!styledRetry.isHovered)
	}

	private func renderedImage(_ view: NSView) throws -> Data
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
