import Foundation

@testable import CodexGUI

/// Finishes real parsing, then holds one result while a newer transcript is accepted.
@MainActor
final class TranscriptPreparationTestGate
{
	private let cache = ConversationContentCache()
	private let heldBody: String
	private var suspended: CheckedContinuation<Void, Never>?
	private var started = false
	private var released = false
	private var startWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

	init(heldBody: String)
	{
		self.heldBody = heldBody
	}

	func prepare(
		_ key: TranscriptPreparationCoordinator.ContentKey
	) async -> PreparedConversationContent
	{
		let content = await cache.content(
			body: key.body,
			markdown: key.markdown,
			preserveSoftBreaks: key.preserveSoftBreaks
		)
		guard key.body == heldBody, !released
		else
		{
			return content
		}
		// Intentionally finish obsolete work even after cancellation, as a worker may do.
		await withCheckedContinuation
		{
			suspended = $0
			started = true
			let waiters = Array(startWaiters.values)
			startWaiters.removeAll()
			for waiter in waiters
			{
				waiter.resume(returning: true)
			}
		}
		return content
	}

	func waitUntilStarted() async -> Bool
	{
		let id = UUID()
		return await withTaskCancellationHandler
		{
			await withCheckedContinuation
			{
				if started
				{
					$0.resume(returning: true)
				}
				else if released || Task.isCancelled
				{
					$0.resume(returning: false)
				}
				else
				{
					startWaiters[id] = $0
				}
			}
		}
		onCancel:
		{
			Task
			{
				@MainActor in
				self.startWaiters.removeValue(forKey: id)?.resume(returning: false)
			}
		}
	}

	func release()
	{
		released = true
		suspended?.resume()
		suspended = nil
		let waiters = Array(startWaiters.values)
		startWaiters.removeAll()
		for waiter in waiters
		{
			waiter.resume(returning: false)
		}
	}
}
