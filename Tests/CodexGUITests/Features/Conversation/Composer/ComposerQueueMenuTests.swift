import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct ComposerQueueMenuTests
{
	@Test func menuMatchesReferenceGeometryAndRoutesCapturedActionsAcrossThemes() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let fixture = ComposerQueueTestFixture(
				texts: ["Queued input"],
				queueFrame: NSRect(
					x: 20,
					y: 200,
					width: 700,
					height: 130
				)
			)
			defer
			{
				fixture.close()
			}
			let window = fixture.window
			let queue = fixture.queue
			var toggles: [Bool] = []
			queue.onSetQueueingEnabled =
			{
				toggles.append($0)
			}
			let row = try #require(queue.messageRows.first)
			for appearance in [NSAppearance.Name.aqua, .darkAqua, .aqua]
			{
				window.appearance = NSAppearance(named: appearance)
				queue.clearActionHovers()
				let idleSteer = try bitmap(row.steer)
				let idleRemove = try bitmap(row.remove)
				row.steer.mouseEntered(with: NSEvent())
				#expect(try bitmap(row.steer).tiffRepresentation != idleSteer.tiffRepresentation)
				row.remove.mouseEntered(with: NSEvent())
				#expect(try bitmap(row.steer).tiffRepresentation == idleSteer.tiffRepresentation)
				#expect(row.overflow.dispatchConfiguredAction())
				let menu = try #require(queue.queueMenu)
				defer
				{
					menu.close()
				}
				let surface = try #require(menu.host.primarySurface)
				let anchor = window.convertToScreen(row.overflow.convert(
					row.overflow.bounds,
					to: nil
				))
				let frame = menu.host.panel.convertToScreen(surface.frame)
				#expect(abs(frame.maxX - anchor.maxX) < 0.6)
				#expect(abs(anchor.minY - frame.maxY - 5) < 0.6)
				#expect(abs(frame.height - 93.7109375) < 0.01)
				#expect(abs(frame.width - 154.04) < 2)
				#expect(row.overflow.menuIsOpen)
				#expect(try bitmap(row.remove).tiffRepresentation == idleRemove.tiffRepresentation)
				#expect(menu.rows.map(\.title) == [
					"Edit message",
					"Open in side chat",
					"Turn off queueing"
				])
				#expect(!menu.rows[1].isEnabled)
				#expect(!menu.rows[1].accessibilityPerformPress())
				for item in menu.rows
				{
					#expect(abs(item.frame.height - 28.5703125) <= 0.25)
					#expect(item.font?.pointSize == 13)
					let textRect = item.titleLabel.alignmentRect(forFrame: item.titleLabel.frame)
					#expect(abs(textRect.minX - item.iconView.frame.maxX - 6) < 0.01)
					#expect((item.titleLabel.cell?.cellSize.width ?? 0) <= item.titleLabel.frame
						.width + 0.5)
					#expect(item.iconView.image?.size == NSSize(
						width: 16,
						height: 16
					))
				}
				menu.host.panel.makeFirstResponder(menu.rows[0])
				for (code, index) in [(UInt16(125), 2), (126, 0), (126, 2)]
				{
					#expect(!menu.host.shouldForward(try key(
						code,
						in: menu.host.panel
					)))
					#expect(menu.host.panel.firstResponder === menu.rows[index])
				}
				#expect(menu.rows[2].menuHighlighted)
				#expect(!menu.rows[0].menuHighlighted)
				#expect(!menu.host.shouldForward(try key(
					36,
					in: menu.host.panel
				)))
				#expect(!menu.host.isShown)
				#expect(!row.overflow.menuIsOpen)
			}
			#expect(toggles == [false, false, false])
			#expect(row.overflow.dispatchConfiguredAction())
			let oldMenu = try #require(queue.queueMenu)
			queue.render(fixture.presentation)
			#expect(!oldMenu.host.isShown)
		}
	}

	@Test func editCapturesItsMessageAndCallbackAndRejectsOccupiedOrReservedDrafts() throws
	{
		_ = NSApplication.shared
		let queue = ComposerQueueView()
		let message = ComposerQueueTestFixture.message("Edit captured input")
		var model = ComposerQueueTestFixture.model(messages: [message])
		var edits: [QueuedComposerMessage] = []
		queue.onEdit =
		{
			edits.append($0)
		}
		queue
			.render(ConversationPresentation(WorkspaceSelectors.snapshot(
				model: model,
				now: Date()
			))
			.composer)
		let captured = queue.actionsMenu(for: message)
		let edit = try #require(captured.items.first)
		#expect(edit.isEnabled)
		var replacementCalls = 0
		queue.onEdit =
		{
			_ in replacementCalls += 1
		}
		#expect(NSApp.sendAction(
			try #require(edit.action),
			to: edit.target,
			from: edit
		))
		#expect(edits == [message])
		#expect(replacementCalls == 0)

		for condition in ["text", "context", "editing", "reserved"]
		{
			model.composer.drafts[.thread("chat")] = ComposerDraft(
				text: condition == "text" ? "Keep this draft" : "",
				context: condition == "context" ? [ComposerContextItem(
					kind: .fileReference,
					title: "File"
				)] : [],
				queuedMessages: [message]
			)
			var presentation = ConversationPresentation(WorkspaceSelectors.snapshot(
				model: model,
				now: Date()
			)).composer
			presentation.isEditingQueuedMessage = condition == "editing"
			presentation.reservedQueuedMessageIDs = condition == "reserved" ? [message.id] : []
			queue.render(presentation)
			let guarded = queue.actionsMenu(for: message)
			#expect(guarded.items.first?.isEnabled == false)
			let custom = ComposerQueueMenu(menu: guarded)
			#expect(!custom.rows[0].accessibilityPerformPress())
			#expect(edits == [message])
			#expect(replacementCalls == 0)
		}
	}

	private func key(
		_ code: UInt16,
		in window: NSWindow
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

	private func bitmap(_ view: NSView) throws -> NSBitmapImageRep
	{
		let image = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
		image.hasAlpha = true
		view.cacheDisplay(
			in: view.bounds,
			to: image
		)
		return image
	}

}
