import AppKit
import Testing

@testable import CodexGUI

@MainActor
// Native sheet focus and keyboard routing are application-wide while dismissal awaits.
@Suite(
	.serialized,
	.testTiming
)
struct TaskDeletionConfirmationTests
{
	@Test func unavailableTaskManagementDoesNotPresentAConfirmation() async throws
	{
		let timing = TestTiming.begin("test.body")
		defer
		{
			timing.end()
		}
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			let controller = NavigationViewController()
			let parent = makeParentWindow(controller)
			defer
			{
				parent.close()
			}
			var deletedTaskIDs: [String] = []
			controller.onDeleteTask =
			{
				deletedTaskIDs.append($0)
			}
			controller.confirmDeleteTask(try makeThread())
			#expect(parent.attachedSheet == nil)
			#expect(deletedTaskIDs.isEmpty)
		}
	}

	@Test func cancellationActionsDismissWithoutDeletingAndAllowAnotherPresentation() async throws
	{
		let timing = TestTiming.begin("test.body")
		defer
		{
			timing.end()
		}
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			let controller = NavigationViewController()
			let parent = makeParentWindow(controller)
			defer
			{
				parent.close()
			}
			controller.canManageSidebarTasks = true
			let thread = try makeThread()
			var deletedTaskIDs: [String] = []
			controller.onDeleteTask =
			{
				deletedTaskIDs.append($0)
			}

			for action in CancellationAction.allCases
			{
				controller.confirmDeleteTask(thread)
				let panel = try #require(parent.attachedSheet as? TaskDeletionConfirmationPanel)
				let dialog = try #require(panel
					.contentViewController as? TaskDeletionConfirmationView)
				#expect(deletedTaskIDs.isEmpty)
				#expect(panel.defaultButtonCell === dialog.cancelButton.cell)
				#expect(dialog.deleteButton.keyEquivalent.isEmpty)

				let actionTiming = TestTiming.begin(
					"sheet.action",
					detail: "\(action)"
				)
				// Button cases verify target-action wiring; key cases retain native event routing.
				switch action
				{
				case .cancel:
					try #require(dialog.cancelButton.dispatchConfiguredAction())
				case .close:
					try #require(dialog.closeButton.dispatchConfiguredAction())
				case .escape:
					panel.cancelOperation(nil)
				case .returnKey:
					try sendKeyEvent(
						to: panel,
						characters: "\r",
						keyCode: 36
					)
				case .keypadEnter:
					try sendKeyEvent(
						to: panel,
						characters: "\u{3}",
						keyCode: 76
					)
				}
				actionTiming.end()
				let dismissalTiming = TestTiming.begin(
					"sheet.dismissal",
					detail: "\(action)"
				)
				await waitForDismissal(parent)
				dismissalTiming.end()
				#expect(parent.attachedSheet == nil)
				#expect(deletedTaskIDs.isEmpty)
			}
		}
	}

	@Test func deleteUsesTheCapturedTaskAndCallbackOnce() async throws
	{
		let timing = TestTiming.begin("test.body")
		defer
		{
			timing.end()
		}
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			let controller = NavigationViewController()
			let parent = makeParentWindow(controller)
			defer
			{
				parent.close()
			}
			controller.canManageSidebarTasks = true
			let thread = try makeThread()
			controller.selectedThreadID = "another-task"
			var requestingOwnerTaskIDs: [String] = []
			var replacementOwnerTaskIDs: [String] = []
			controller.onDeleteTask =
			{
				requestingOwnerTaskIDs.append($0)
			}
			controller.confirmDeleteTask(thread)
			let panel = try #require(parent.attachedSheet as? TaskDeletionConfirmationPanel)
			let dialog = try #require(panel.contentViewController as? TaskDeletionConfirmationView)

			controller.onDeleteTask =
			{
				replacementOwnerTaskIDs.append($0)
			}
			let actionTiming = TestTiming.begin(
				"sheet.action",
				detail: "delete"
			)
			try #require(dialog.deleteButton.dispatchConfiguredAction())
			actionTiming.end()
			let dismissalTiming = TestTiming.begin(
				"sheet.dismissal",
				detail: "delete"
			)
			await waitForDismissal(parent)
			dismissalTiming.end()
			#expect(parent.attachedSheet == nil)
			#expect(requestingOwnerTaskIDs == [thread.id])
			#expect(replacementOwnerTaskIDs.isEmpty)

			try #require(dialog.deleteButton.dispatchConfiguredAction())
			#expect(requestingOwnerTaskIDs == [thread.id])
		}
	}

	@Test(arguments: [false, true])
	func deleteRejectsChangedOwnershipOrRevokedManagement(changeOwnership: Bool) async throws
	{
		let timing = TestTiming.begin("test.body")
		defer
		{
			timing.end()
		}
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			let controller = NavigationViewController()
			let parent = makeParentWindow(controller)
			defer
			{
				parent.close()
			}
			controller.canManageSidebarTasks = true
			controller.modalScope = makeScope(selectionEpoch: 1)
			var deletedTaskIDs: [String] = []
			controller.confirmDeleteTask(
				try makeThread(),
				completion:
				{
					deletedTaskIDs.append($0)
				}
			)
			let panel = try #require(parent.attachedSheet as? TaskDeletionConfirmationPanel)
			let dialog = try #require(panel.contentViewController as? TaskDeletionConfirmationView)

			if changeOwnership
			{
				controller.modalScope = makeScope(selectionEpoch: 2)
			}
			else
			{
				controller.canManageSidebarTasks = false
			}
			let actionTiming = TestTiming.begin(
				"sheet.action",
				detail: "reject-delete"
			)
			try #require(dialog.deleteButton.dispatchConfiguredAction())
			actionTiming.end()
			let dismissalTiming = TestTiming.begin(
				"sheet.dismissal",
				detail: "reject-delete"
			)
			await waitForDismissal(parent)
			dismissalTiming.end()
			#expect(parent.attachedSheet == nil)
			#expect(deletedTaskIDs.isEmpty)
		}
	}

	private enum CancellationAction: CaseIterable
	{
		case cancel
		case close
		case escape
		case returnKey
		case keypadEnter
	}

	private func makeThread() throws -> ThreadSummary
	{
		try #require(ThreadSummary(json: ["id": "requested-task", "name": "Requested task"]))
	}

	private func makeScope(selectionEpoch: Int) -> NavigationViewController.ModalScope
	{
		NavigationViewController.ModalScope(
			owner: nil,
			selectionEpoch: selectionEpoch,
			conversation: .thread("requested-task"),
			draftLifetime: 0,
			projectPath: "/tmp/task-deletion-confirmation"
		)
	}

	private func makeParentWindow(_ controller: NavigationViewController) -> NSWindow
	{
		_ = NSApplication.shared
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
		window.contentViewController = controller
		window.orderFront(nil)
		return window
	}

	private func waitForDismissal(_ parent: NSWindow) async
	{
		for _ in 0 ..< 100
		{
			if parent.attachedSheet == nil
			{
				return
			}
			try? await Task.sleep(for: .milliseconds(10))
		}
	}

	private func sendKeyEvent(
		to panel: NSPanel,
		characters: String,
		keyCode: UInt16
	) throws
	{
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
	}

}
