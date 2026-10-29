import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct ComposerQueueControlTests
{
	@Test func rowActionsAndReorderingTargetTheirMessageWithoutEditingTheComposer() throws
	{
		_ = NSApplication.shared
		let first = ComposerQueueTestFixture.message("Next task")
		let second = ComposerQueueTestFixture.message("Later task")
		var model = ComposerQueueTestFixture.model(
			messages: [first, second],
			draft: "Unsent draft"
		)
		model.execution = ExecutionModel(
			activeThreadID: "chat",
			activeTurnID: "turn",
			state: .running
		)
		let controller = ConversationViewController()
		controller.loadViewIfNeeded()
		var steering: [UUID] = []
		var removals: [UUID] = []
		var orders: [[UUID]] = []
		var queueing: [Bool] = []
		controller.onSteerQueuedMessage =
		{
			steering.append($0)
		}
		controller.onRemoveQueuedMessage =
		{
			id, _ in removals.append(id)
		}
		controller.onReorderQueuedMessages =
		{
			orders.append($0)
		}
		controller.onSetQueueingEnabled =
		{
			queueing.append($0)
		}
		controller.render(WorkspaceSelectors.snapshot(
			model: model,
			now: Date()
		))
		let row = try #require(controller.composerQueueView.messageRows.first)
		#expect(row.preview.isEnabled)
		#expect(row.steer.dispatchConfiguredAction())
		#expect(steering == [first.id])
		#expect(row.remove.dispatchConfiguredAction())
		#expect(removals == [first.id])
		#expect(controller.composerQueueView.moveMessage(
			first.id,
			to: 2
		))
		#expect(orders == [[second.id, first.id]])
		let menu = controller.composerQueueView.actionsMenu(for: first)
		let toggle = try #require(menu.items.last)
		#expect(NSApp.sendAction(
			try #require(toggle.action),
			to: toggle.target,
			from: toggle
		))
		#expect(queueing == [false])
		#expect(controller.composer.draftText == "Unsent draft")

		var edits: [QueuedComposerMessage] = []
		controller.onBeginEditingQueuedMessage =
		{
			edits.append($0)
		}
		model.composer.drafts[.thread("chat")]?.text = ""
		controller.render(WorkspaceSelectors.snapshot(
			model: model,
			now: Date()
		))
		let editable = controller.composerQueueView.actionsMenu(for: second)
		let edit = try #require(editable.items.first)
		#expect(edit.isEnabled)
		#expect(NSApp.sendAction(
			try #require(edit.action),
			to: edit.target,
			from: edit
		))
		#expect(edits == [second])
		// Restore the occupied composer before checking the two resume routes.
		model.composer.drafts[.thread("chat")]?.text = "Unsent draft"

		var resumes = 0
		controller.onResumeMessageQueue =
		{
			resumes += 1
		}
		model.execution = ExecutionModel(state: .stopped)
		model.composer.drafts[.thread("chat")]?.queuePaused = true
		controller.render(WorkspaceSelectors.snapshot(
			model: model,
			now: Date()
		))
		#expect(!controller.composerQueueView.isHidden)
		#expect(controller.resumeButton.isHidden)
		#expect(controller.composerQueueView.pauseLabel
			.stringValue == "Queue paused because you interrupted")
		#expect(controller.composerQueueView.resumeButton.dispatchConfiguredAction())
		#expect(resumes == 1)
		model.composer.drafts[.thread("chat")]?.text = ""
		controller.render(WorkspaceSelectors.snapshot(
			model: model,
			now: Date()
		))
		#expect(!controller.resumeButton.isHidden)
		#expect(controller.sendButton.isHidden)
		#expect(controller.resumeButton.dispatchConfiguredAction())
		#expect(resumes == 2)
		model.composer.drafts[.thread("chat")]?.queuedMessages = []
		model.composer.drafts[.thread("chat")]?.queuePaused = false
		controller.render(WorkspaceSelectors.snapshot(
			model: model,
			now: Date()
		))
		#expect(controller.composerQueueView.messageRows.isEmpty)
		#expect(controller.composerQueueView.isHidden)
	}

	@Test func panelKeepsReferenceGeometryAndSemanticAppearanceAcrossWidths() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 760,
					height: 600
				),
				styleMask: [.titled, .resizable],
				backing: .buffered,
				defer: false
			)
			window.prepareForTesting()
			defer
			{
				window.close()
			}
			let controller = ConversationViewController()
			window.contentViewController = controller
			let messages = ["Short", String(
				repeating: "A long message ",
				count: 12
			)]
			.map(ComposerQueueTestFixture.message)
			var model = ComposerQueueTestFixture.model(
				messages: messages,
				paused: true
			)
			model.execution = ExecutionModel(
				activeThreadID: "chat",
				activeTurnID: "turn",
				state: .running
			)
			controller.render(WorkspaceSelectors.snapshot(
				model: model,
				now: Date()
			))
			for appearance in [NSAppearance.Name.aqua, .darkAqua, .aqua]
			{
				window.appearance = NSAppearance(named: appearance)
				for width: CGFloat in [760, 520]
				{
					window.setContentSize(NSSize(
						width: width,
						height: 600
					))
					window.contentView?.layoutSubtreeIfNeeded()
					let rows = controller.composerQueueView.messageRows
					#expect(rows.count == 2)
					let first = try #require(rows.first)
					let second = try #require(rows.last)
					#expect(abs(first.frame.height - 32) < 0.1)
					#expect(first.preview.font?.pointSize == 14)
					let previewColor = try #require(first.preview.attributedTitle.attribute(
						.foregroundColor,
						at: 0,
						effectiveRange: nil
					) as? NSColor)
					var previewAlpha: CGFloat = 0
					first.preview.effectiveAppearance.performAsCurrentDrawingAppearance
					{
						previewAlpha = previewColor.usingColorSpace(.sRGB)?.alphaComponent ?? 0
					}
					#expect(abs(previewAlpha - 1) < 0.001)

					#expect(first.steer.frame.height == 24)
					#expect(first.steer.frame.width == first.steer.intrinsicContentSize.width)
					#expect(first.remove.frame.width == 24)
					#expect(first.overflow.frame.width == 24)
					#expect(controller.composerQueueView.resumeButton.frame.width == 85)
					#expect(first.steer.image?.size.width == 14)
					#expect(first.remove.image?.size.width == 14)
					#expect(first.overflow.image?.size.width == 14)
					#expect(abs(abs(first.frame.minY - second.frame.minY) - 33) < 0.1)
					#expect(controller.composerQueueView.resumeButton.frame.height == 24)
					#expect(controller.resumeButton.frame.height == 28)
					#expect(controller.resumeButton.image?.size == NSSize(
						width: 16,
						height: 16
					))
					let pauseLabel = controller.composerQueueView.pauseLabel
					#expect(pauseLabel.stringValue == "Queue paused")
					#expect(abs(pauseLabel.alignmentRect(forFrame: pauseLabel.frame).minX - 32) <
						0.1)
					let divider = controller.composerQueueView.headerDivider
					#expect(divider.frame.height == 1)
					#expect(divider.frame.width == first.frame.width)
					#expect(abs(divider.convert(
						divider.bounds,
						to: first
					).minY - first.bounds
						.maxY - 1) < 0.1)
					let textLeft = first.convert(
						first.preview.bounds,
						from: first.preview
					).minX
					#expect(abs(textLeft - 32) < 0.1)
					let firstRight = controller.composerQueueView.convert(
						first.overflow.bounds,
						from: first.overflow
					).maxX
					let secondRight = controller.composerQueueView.convert(
						second.overflow.bounds,
						from: second.overflow
					).maxX
					#expect(abs(firstRight - secondRight) < 0.1)
					#expect(second.preview.bounds.width > 0)
					let queue = controller.view.convert(
						controller.composerQueueView.bounds,
						from: controller.composerQueueView
					)
					let composer = controller.view.convert(
						controller.composerSurface.bounds,
						from: controller.composerSurface
					)
					#expect(abs(queue.minX - composer.minX - 13) < 0.1)
					#expect(abs(queue.maxY - composer.maxY - 105) < 0.1)
					#expect(controller.composerQueueView.layer?
						.backgroundColor == AppKitColorResolution.resolvedCGColor(
							AppKitColorTokens.composerQueue,
							for: controller.composerQueueView
						))
				}
			}
		}
	}

}
