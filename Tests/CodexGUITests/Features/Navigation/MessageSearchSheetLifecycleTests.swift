import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite(.serialized)
struct MessageSearchSheetLifecycleTests
{
	@Test func endingTheSheetExternallyRetiresSearchAndAllowsAnotherPresentation() async throws
	{
		let parent = makeParentWindow()
		let controller = MessageSearchController()
		defer
		{
			controller.dismiss()
			parent.close()
		}
		let (dismissals, continuation) = AsyncStream<Void>.makeStream()
		defer
		{
			continuation.finish()
		}
		var dismissalCount = 0
		controller.onDismiss =
		{
			dismissalCount += 1
			continuation.yield(())
		}
		controller.present(in: parent)
		let first = try #require(parent.attachedSheet)
		parent.endSheet(first)
		let dismissed = await waitForDismissal(dismissals)
		try #require(dismissed)
		#expect(dismissalCount == 1)
		controller.present(in: parent)
		let replacement = try #require(parent.attachedSheet)
		#expect(replacement !== first)
		controller.dismiss()
		#expect(dismissalCount == 2)
	}

	@Test func nativeCloseRetiresOnlyItsSheetAndDoesNotDismissTheReplacementOwner() throws
	{
		let parent = makeParentWindow()
		let controller = MessageSearchController()
		defer
		{
			controller.dismiss()
			parent.close()
		}
		var retiredDismissals = 0
		var currentDismissals = 0
		controller.onDismiss =
		{
			retiredDismissals += 1
		}
		controller.present(in: parent)
		let retiredSheet = try #require(parent.attachedSheet)
		retiredSheet.close()
		#expect(parent.attachedSheet == nil)
		#expect(retiredDismissals == 1)
		controller.onDismiss =
		{
			currentDismissals += 1
		}
		controller.present(in: parent)
		let replacement = try #require(parent.attachedSheet)
		#expect(replacement !== retiredSheet)
		controller.windowWillClose(Notification(
			name: NSWindow.willCloseNotification,
			object: retiredSheet
		))
		#expect(parent.attachedSheet === replacement)
		#expect(currentDismissals == 0)
		controller.dismiss()
		controller.dismiss()
		#expect(retiredDismissals == 1)
		#expect(currentDismissals == 1)
	}

	private func makeParentWindow() -> NSWindow
	{
		_ = NSApplication.shared
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 760,
				height: 580
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		return window
	}

	private func waitForDismissal(_ dismissals: AsyncStream<Void>) async -> Bool
	{
		await withTaskGroup(of: Bool.self)
		{
			group in
			group.addTask
			{
				for await _ in dismissals
				{
					return true
				}
				return false
			}
			group.addTask
			{
				try? await Task.sleep(for: .seconds(3))
				return false
			}
			let dismissed = await group.next() ?? false
			group.cancelAll()
			return dismissed
		}
	}
}
