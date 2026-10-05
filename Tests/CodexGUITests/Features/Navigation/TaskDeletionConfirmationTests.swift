import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite(.serialized)
struct TaskDeletionConfirmationTests
{
	@Test func unavailableTaskManagementDoesNotPresentAConfirmation() throws
	{
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

	@Test func cancellationActionsDismissWithoutDeletingAndAllowAnotherPresentation() async throws
	{
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
			let dialog = try #require(panel.contentViewController as? TaskDeletionConfirmationView)
			#expect(deletedTaskIDs.isEmpty)
			#expect(panel.defaultButtonCell === dialog.cancelButton.cell)
			#expect(dialog.deleteButton.keyEquivalent.isEmpty)

			switch action
			{
			case .cancel:
				dialog.cancelButton.performClick(nil)
			case .close:
				dialog.closeButton.performClick(nil)
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
			await waitForDismissal(parent)
			#expect(parent.attachedSheet == nil)
			#expect(deletedTaskIDs.isEmpty)
		}
	}

	@Test func deleteUsesTheCapturedTaskAndCallbackOnce() async throws
	{
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
		dialog.deleteButton.performClick(nil)
		await waitForDismissal(parent)
		#expect(parent.attachedSheet == nil)
		#expect(requestingOwnerTaskIDs == [thread.id])
		#expect(replacementOwnerTaskIDs.isEmpty)

		dialog.deleteButton.performClick(nil)
		#expect(requestingOwnerTaskIDs == [thread.id])
	}

	@Test(arguments: [false, true])
	func deleteRejectsChangedOwnershipOrRevokedManagement(changeOwnership: Bool) async throws
	{
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
		dialog.deleteButton.performClick(nil)
		await waitForDismissal(parent)
		#expect(parent.attachedSheet == nil)
		#expect(deletedTaskIDs.isEmpty)
	}

	@Test func dialogMatchesTheWarningAndKeepsHorizontalActionsUnclipped() throws
	{
		_ = NSApplication.shared
		let dialog = TaskDeletionConfirmationView()
		_ = dialog.view
		dialog.view.frame.size = dialog.view.fittingSize
		dialog.view.layoutSubtreeIfNeeded()
		#expect(dialog.headingLabel.stringValue == "Delete task?")
		#expect(dialog.warningLabel.stringValue ==
			"This permanently deletes the task and its subagent tasks.\nThis cannot be undone.")
		#expect(dialog.cancelButton.title == "Cancel")
		#expect(dialog.deleteButton.title == "Delete")

		let cancelFrame = frame(
			of: dialog.cancelButton,
			in: dialog.view
		)
		let deleteFrame = frame(
			of: dialog.deleteButton,
			in: dialog.view
		)
		let headingFrame = alignmentFrame(
			of: dialog.headingLabel,
			in: dialog.view
		)
		let deleteAlignmentFrame = alignmentFrame(
			of: dialog.deleteButton,
			in: dialog.view
		)
		#expect(abs(cancelFrame.midY - deleteFrame.midY) < 1)
		#expect(cancelFrame.maxX < deleteFrame.minX)
		#expect(cancelFrame.minX > dialog.view.bounds.midX)
		let trailingInset = dialog.view.bounds.maxX - deleteAlignmentFrame.maxX
		#expect(abs(trailingInset - headingFrame.minX) < 1)

		let controls: [NSView] = [dialog.headingLabel,
									dialog.warningLabel,
									dialog.cancelButton,
									dialog.deleteButton,
									dialog.closeButton]
		for control in controls
		{
			#expect(dialog.view.bounds.contains(frame(
				of: control,
				in: dialog.view
			)))
		}
		let warningCell = try #require(dialog.warningLabel.cell)
		let requiredWarningSize = warningCell.cellSize(forBounds: dialog.warningLabel.bounds)
		#expect(requiredWarningSize.height <= dialog.warningLabel.bounds.height + 1)
		let warningFont = try #require(dialog.warningLabel.font)
		#expect(dialog.warningLabel.bounds.height >= warningFont.pointSize * 2)
		try verifyPrimaryContentAdaptsToAppearance(dialog)
		try writeEvidence(dialog)
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

	private func frame(
		of control: NSView,
		in root: NSView
	) -> NSRect
	{
		control.convert(
			control.bounds,
			to: root
		)
	}

	private func alignmentFrame(
		of control: NSView,
		in root: NSView
	) -> NSRect
	{
		control.convert(
			control.alignmentRect(forFrame: control.bounds),
			to: root
		)
	}

	private func verifyPrimaryContentAdaptsToAppearance(
		_ dialog: TaskDeletionConfirmationView
	) throws
	{
		let headingColor = try #require(dialog.headingLabel.textColor)
		let closeColor = try #require(dialog.closeButton.contentTintColor)
		for appearanceName in [NSAppearance.Name.aqua, .darkAqua]
		{
			let appearance = try #require(NSAppearance(named: appearanceName))
			let shouldUseLightForeground = appearanceName == .darkAqua
			for color in [headingColor, closeColor]
			{
				var resolvedColor: NSColor?
				appearance.performAsCurrentDrawingAppearance
				{
					resolvedColor = color.usingColorSpace(.deviceRGB)
				}
				let foreground = try #require(resolvedColor)
				let brightness =
					(foreground.redComponent + foreground.greenComponent + foreground
						.blueComponent) / 3
				#expect((brightness > 0.5) == shouldUseLightForeground)
			}
		}
	}

	private func writeEvidence(_ dialog: TaskDeletionConfirmationView) throws
	{
		guard let directory = ProcessInfo.processInfo.environment["CODEX_GUI_UI_EVIDENCE_DIRECTORY"]
		else
		{
			return
		}
		let output = URL(fileURLWithPath: directory)
		try FileManager.default.createDirectory(
			at: output,
			withIntermediateDirectories: true
		)
		for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)]
		{
			dialog.view.appearance = NSAppearance(named: appearance)
			dialog.view.layoutSubtreeIfNeeded()
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
			try png.write(to: output.appendingPathComponent("task-deletion-\(name).png"))
		}
	}
}
