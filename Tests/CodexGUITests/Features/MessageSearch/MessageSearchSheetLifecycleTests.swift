import AppKit
import Testing

@testable import CodexGUI

@MainActor
// Sheet presentation and asynchronous dismissal share AppKit modal lifecycle.
@Suite(.serialized)
struct MessageSearchSheetLifecycleTests
{
	@Test func endingTheSheetExternallyRetiresSearchAndAllowsAnotherPresentation() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			let native = TestTiming.begin("native.body")
			defer
			{
				native.end()
			}
			native.mark("parent.begin")
			let parent = makeParentWindow(timing: native)
			native.mark("parent.end")
			native.mark("controller.begin")
			let controller = MessageSearchController()
			native.mark("controller.end")
			defer
			{
				native.mark("cleanup.begin")
				controller.dismiss()
				parent.close()
				native.mark("cleanup.end")
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
				native.mark("dismissal.\(dismissalCount).produced")
				continuation.yield(())
			}
			native.mark("present.first.begin")
			controller.present(in: parent)
			native.mark("present.first.end")
			let first = try #require(parent.attachedSheet)
			native.mark("endSheet.begin")
			parent.endSheet(first)
			native.mark("endSheet.end")
			native.mark("dismissal.await.begin")
			// AppKit can finish dismissal synchronously during endSheet.
			// Await the publication only when its callback has not already arrived.
			let dismissed: Bool
			if dismissalCount == 0
			{
				dismissed = await waitForDismissal(dismissals)
			}
			else
			{
				dismissed = dismissalCount > 0
			}
			native.mark("dismissal.await.end")
			try #require(dismissed)
			#expect(dismissalCount == 1)
			native.mark("present.second.begin")
			controller.present(in: parent)
			native.mark("present.second.end")
			let replacement = try #require(parent.attachedSheet)
			#expect(replacement !== first)
			native.mark("dismiss.second.begin")
			controller.dismiss()
			native.mark("dismiss.second.end")
			#expect(dismissalCount == 2)
		}
	}

	@Test func nativeCloseRetiresOnlyItsSheetAndDoesNotDismissTheReplacementOwner() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			let native = TestTiming.begin("native.body")
			defer
			{
				native.end()
			}
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
	}

	private func makeParentWindow(timing: TestTiming.Span? = nil) -> NSWindow
	{
		timing?.mark("application.shared.begin")
		_ = NSApplication.shared
		timing?.mark("application.shared.end")
		timing?.mark("window.init.begin")
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
		timing?.mark("window.init.end")
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
