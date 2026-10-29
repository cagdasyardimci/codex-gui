import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct ComposerQueueReorderingTests
{
	@Test func recordedSwapsMoveTheWholeDimmedRowAndSettleBeforeCommitting() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let fixture = ComposerQueueTestFixture()
			defer
			{
				fixture.close()
			}
			let queue = fixture.queue
			var presentation = fixture.presentation
			var orders: [[UUID]] = []
			queue.onReorder =
			{
				orders.append($0)
			}
			for (source, target) in [(1, 0), (1, 0), (2, 1)]
			{
				fixture.window.layoutIfNeeded()
				let before = queue.messageRows
				let row = before[source]
				let original = queue.convert(
					row.bounds,
					from: row
				)
				let targetFrame = queue.convert(
					before[target].bounds,
					from: before[target]
				)
				let control = queue.convert(
					row.steer.bounds,
					from: row.steer
				)
				let down = fixture.window.contentView!.convert(
					NSPoint(
						x: original.minX + 5,
						y: original.midY
					),
					from: queue
				)
				let offset = targetFrame.midY - original.midY + 7
				let held = NSPoint(
					x: down.x,
					y: down.y + offset
				)
				let count = orders.count
				#expect(queue.beginReordering(
					row,
					at: down
				))
				queue.updateReordering(at: held)
				#expect(row.superview === queue)
				#expect(abs(row.frame.minY - original.minY - offset) < 0.1)
				#expect(abs(queue.convert(
					row.steer.bounds,
					from: row.steer
				).minY - control
					.minY - offset) < 0.1)
				#expect(row.alphaValue == 0.6)
				if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
				{
					CATransaction.flush()
					let layer = try #require(before[target].layer)
					let moving = try #require(layer.presentation())
					#expect(abs(moving.position.y - layer.position.y) > 1)
				}
				#expect(orders.count == count)
				#expect(queue.presentation?.queuePaused == true)
				queue.endReordering(at: held)
				#expect(row.alphaValue == 1)
				let settling = try #require(queue.reorderSettlingTask)
				await settling.value
				var expected = before.map(\.message.id)
				expected.insert(
					expected.remove(at: source),
					at: target
				)
				#expect(orders.count == count + 1)
				#expect(orders.last == expected)
				#expect(queue.messageRows.map(\.message.id) == expected)
				#expect(abs(queue.convert(
					row.bounds,
					from: row
				).midY - targetFrame.midY) < 0.1)
				#expect(queue.reorderSession == nil)
				#expect(row.alphaValue == 1)
				// A pending server write must not snap the settled row back to its old slot.
				presentation.reservedQueuedMessageIDs = Set(expected)
				queue.render(presentation)
				fixture.window.layoutIfNeeded()
				#expect(queue.messageRows.map(\.message.id) == expected)
				let messages = Dictionary(uniqueKeysWithValues: presentation.queuedMessages.map
				{
					(
						$0.id,
						$0
					)
				})
				presentation.queuedMessages = expected.compactMap
				{
					messages[$0]
				}
				presentation.reservedQueuedMessageIDs = []
				queue.render(presentation)
				fixture.window.layoutIfNeeded()
				#expect(queue.pendingVisualOrder == nil)
				#expect(queue.presentation?.queuePaused == true)
			}
		}
	}

	@Test func cancellationAndExternalChangesRetireDragWithoutReordering() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let fixture = ComposerQueueTestFixture()
			defer
			{
				fixture.close()
			}
			let queue = fixture.queue
			let expected = fixture.presentation.queuedMessages.map(\.id)
			var orders: [[UUID]] = []
			queue.onReorder =
			{
				orders.append($0)
			}
			let row = queue.messageRows[1]
			let frame = row.convert(
				row.bounds,
				to: nil
			)
			let down = NSPoint(
				x: frame.minX + 5,
				y: frame.midY
			)
			#expect(queue.beginReordering(
				row,
				at: down
			))
			queue.updateReordering(at: NSPoint(
				x: down.x,
				y: down.y + 40
			))
			queue.cancelReordering()
			#expect(queue.messageRows.map(\.message.id) == expected)
			#expect(row.alphaValue == 1)
			#expect(orders.isEmpty)
			#expect(queue.beginReordering(
				row,
				at: down
			))
			queue.endReordering(at: NSPoint(
				x: down.x,
				y: down.y + 40
			))
			let settling = try #require(queue.reorderSettlingTask)
			var changed = fixture.presentation
			changed.queuedMessages.removeLast()
			queue.render(changed)
			await settling.value
			#expect(orders.isEmpty)
			#expect(queue.reorderSession == nil)
			#expect(queue.messageRows.map(\.message.id) == Array(expected.prefix(2)))
			// Restart after cancellation and invalidate an animation already underway.
			// Reduce Motion keeps the before-start case without requiring an interval.
			if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
			{
				queue.render(fixture.presentation)
				fixture.window.layoutIfNeeded()
				let animated = queue.messageRows[1]
				#expect(queue.beginReordering(
					animated,
					at: down
				))
				queue.endReordering(at: NSPoint(
					x: down.x,
					y: down.y + 40
				))
				let settling = try #require(queue.reorderSettlingTask)
				do
				{
					// No suspension yet: further movement comes from the settling task.
					let movement = RowMovementObservation(row: animated)
					defer
					{
						movement.finish()
					}
					let started = await movement.wait()
					try #require(started)
					try #require(queue.reorderSession?.settling == true)
					#expect(orders.isEmpty)
					var changed = fixture.presentation
					changed.queuedMessages.removeLast()
					queue.render(changed)
					await settling.value
					#expect(orders.isEmpty)
					#expect(queue.reorderSession == nil)
					#expect(queue.reorderSettlingTask == nil)
					#expect(queue.messageRows.map(\.message.id) == changed.queuedMessages.map(\.id))
				}
				catch
				{
					queue.cancelReordering()
					await settling.value
					throw error
				}

			}

		}
	}

	@Test func reservationsBlockRowMutationsAndOwnerSwitchRetiresAnActiveDrag() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let fixture = ComposerQueueTestFixture()
			defer
			{
				fixture.close()
			}
			let queue = fixture.queue
			var calls = 0
			queue.onReorder =
			{
				_ in calls += 1
			}
			queue.onRemove =
			{
				_ in calls += 1
			}
			queue.onSteer =
			{
				_ in calls += 1
			}
			var reserved = fixture.presentation
			let id = try #require(reserved.queuedMessages.first?.id)
			reserved.canSteerQueuedMessage = true
			reserved.reservedQueuedMessageIDs = [id]
			queue.render(reserved)
			fixture.window.layoutIfNeeded()
			let row = try #require(queue.messageRows.first)
			#expect(!row.steer.isEnabled)
			#expect(!row.remove.isEnabled)
			#expect(!row.canDrag)
			#expect(!queue.messageRows[1].canDrag)
			#expect(!queue.moveMessage(
				id,
				to: 2
			))
			#expect(!queue.beginReordering(
				row,
				at: .zero
			))
			#expect(!row.remove.dispatchConfiguredAction())
			#expect(!row.steer.dispatchConfiguredAction())
			#expect(calls == 0)

			queue.render(fixture.presentation)
			fixture.window.layoutIfNeeded()
			let active = queue.messageRows[1]
			let frame = active.convert(
				active.bounds,
				to: nil
			)
			let down = NSPoint(
				x: frame.minX + 5,
				y: frame.midY
			)
			#expect(queue.beginReordering(
				active,
				at: down
			))
			queue.updateReordering(at: NSPoint(
				x: down.x,
				y: down.y + 40
			))
			var other = WorkspaceModel(identity: .init(
				sessionID: UUID(),
				canonicalCheckoutPath: "/tmp/queue-other-owner"
			))
			other.conversations.selectedConversation = .thread("another-chat")
			other.composer.drafts[.thread("another-chat")] = ComposerDraft(
				queuedMessages: fixture.presentation.queuedMessages,
				queuePaused: true
			)
			let replacement = ConversationPresentation(WorkspaceSelectors.snapshot(
				model: other,
				now: Date()
			)).composer
			queue.render(replacement)
			queue.endReordering(at: down)
			#expect(queue.reorderSession == nil)
			#expect(queue.reorderSettlingTask == nil)
			#expect(queue.pendingVisualOrder == nil)
			#expect(queue.presentation?.owner == replacement.owner)
			#expect(queue.messageRows.map(\.message.id) == replacement.queuedMessages.map(\.id))
			#expect(calls == 0)
		}
	}

	@MainActor
	private final class RowMovementObservation
	{
		private let row: NSView
		private let heldOrigin: NSPoint
		private let previousPostsFrameChanges: Bool
		private let movements: AsyncStream<Void>
		private let continuation: AsyncStream<Void>.Continuation
		private var observer: NSObjectProtocol?
		private var timeout: Task<Void, Never>?

		init(row: NSView)
		{
			self.row = row
			heldOrigin = row.frame.origin
			previousPostsFrameChanges = row.postsFrameChangedNotifications
			(
				movements,
				continuation
			) = AsyncStream<Void>.makeStream()
			row.postsFrameChangedNotifications = true
			observer = NotificationCenter.default.addObserver(
				forName: NSView.frameDidChangeNotification,
				object: row,
				queue: nil
			)
			{
				[weak self] _ in
				MainActor.assumeIsolated
				{
					self?.recordMovement()
				}
			}
			let completion = continuation
			timeout = Task
			{
				do
				{
					try await Task.sleep(for: .seconds(3))
				}
				catch
				{
					return
				}
				completion.finish()
			}
		}

		func wait() async -> Bool
		{
			var iterator = movements.makeAsyncIterator()
			return await iterator.next() != nil
		}

		func finish()
		{
			timeout?.cancel()
			if let observer
			{
				NotificationCenter.default.removeObserver(observer)
			}
			observer = nil
			continuation.finish()
			row.postsFrameChangedNotifications = previousPostsFrameChanges
		}

		private func recordMovement()
		{
			if row.frame.origin != heldOrigin
			{
				continuation.yield(())
				continuation.finish()
			}
		}
	}

}
