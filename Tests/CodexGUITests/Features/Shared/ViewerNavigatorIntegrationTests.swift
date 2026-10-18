import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct ViewerNavigatorIntegrationTests
{
	@Test func bothViewersResizeThroughTheirInstalledDividerAndRestoreWidth() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let files = FilesViewController()
			let changes = GitChangesViewController()
			let controllers: [NSViewController] = [files, changes]
			var windows: [NSWindow] = []
			defer
			{
				changes.close()
				for window in windows
				{
					window.close()
				}
			}
			var effectiveWidths: [CGFloat] = []
			for controller in controllers
			{
				let window = NSWindow(contentViewController: controller)
				window.isReleasedWhenClosed = false
				windows.append(window)
				window.setContentSize(NSSize(
					width: 720,
					height: 600
				))
				window.layoutIfNeeded()
				controller.view.layoutSubtreeIfNeeded()
				let split = try #require(descendants(controller.view)
					.compactMap
					{
						$0 as? ViewerNavigatorSplitView
					}.first)
				let divider = try #require(descendants(controller.view)
					.first
					{
						$0.accessibilityLabel() == "Resize file navigator"
					})
				let pan = try #require(divider.gestureRecognizers
					.compactMap
					{
						$0 as? NSPanGestureRecognizer
					}.first)
				let action = try #require(pan.action)
				pan.setTranslation(
					NSPoint(
						x: -80,
						y: 0
					),
					in: split
				)
				#expect(NSApp.sendAction(
					action,
					to: pan.target,
					from: pan
				))
				controller.view.layoutSubtreeIfNeeded()
				#expect(abs(split.navigatorWidth - 321) < 1)
				effectiveWidths.append(split.navigatorWidth)
				window.setContentSize(NSSize(
					width: 400,
					height: 600
				))
				window.layoutIfNeeded()
				controller.view.layoutSubtreeIfNeeded()
				#expect(abs(split.navigatorWidth - 235) < 1)
				window.setContentSize(NSSize(
					width: 720,
					height: 600
				))
				window.layoutIfNeeded()
				controller.view.layoutSubtreeIfNeeded()
				#expect(abs(split.navigatorWidth - 321) < 1)
				let toggle = try #require(descendants(controller.view)
					.compactMap
					{
						$0 as? NSButton
					}.first
					{
						["Toggle file navigator", "Toggle changed-file navigator"]
							.contains($0.accessibilityLabel() ?? "")
					})
				#expect(toggle.dispatchConfiguredAction())
				controller.view.layoutSubtreeIfNeeded()
				#expect(!split.isNavigatorVisible)
				#expect(abs(split.navigatorWidth) < 1)
				#expect(divider.isHidden)
				#expect(toggle.dispatchConfiguredAction())
				controller.view.layoutSubtreeIfNeeded()
				#expect(split.isNavigatorVisible)
				#expect(abs(split.navigatorWidth - 321) < 1)
				for name: NSAppearance.Name in [.aqua, .darkAqua]
				{
					window.appearance = NSAppearance(named: name)
					controller.view.layoutSubtreeIfNeeded()
					#expect(abs(split.navigatorWidth - 321) < 1)
					#expect(!divider.isHidden)
				}
			}
			#expect(effectiveWidths.count == 2)
			#expect(abs(effectiveWidths[0] - effectiveWidths[1]) < 1)
		}
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap
		{
			descendants($0)
		}
	}
}
