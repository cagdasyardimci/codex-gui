import AppKit

@MainActor
final class FullAccessConfirmationPanel: NSPanel
{
	private var dismissalFinished = false
	private var hasCompletedDecision = false
	private var dismissalWaiters: [UUID: AsyncStream<Void>.Continuation] = [:]

	/// The sheet completion, rather than animation timing, acknowledges its final state.
	func waitForDismissal() async throws
	{
		try Task.checkCancellation()
		guard !dismissalFinished
		else
		{
			return
		}
		let id = UUID()
		let checkpoint = AsyncStream<Void>.makeStream()
		dismissalWaiters[id] = checkpoint.continuation
		defer
		{
			dismissalWaiters.removeValue(forKey: id)
			checkpoint.continuation.finish()
		}
		for await _ in checkpoint.stream
		{
			try Task.checkCancellation()
			return
		}
		throw CancellationError()
	}

	func finishDismissal()
	{
		dismissalFinished = true
		let waiters = Array(dismissalWaiters.values)
		dismissalWaiters.removeAll()
		for waiter in waiters
		{
			waiter.yield(())
			waiter.finish()
		}
	}

	override var canBecomeKey: Bool
	{
		true
	}

	override func cancelOperation(_ sender: Any?)
	{
		finishDecision(false)
	}

	override func sendEvent(_ event: NSEvent)
	{
		if sheetParent != nil, event.type == .keyDown,
			event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
			(firstResponder as? NSTextView)?.hasMarkedText() != true
		{
			switch event.charactersIgnoringModifiers
			{
			case "\r", "\u{3}":
				finishDecision(true)
				return
			case "\u{1b}":
				finishDecision(false)
				return
			default:
				break
			}
		}
		super.sendEvent(event)
	}

	private func finishDecision(_ confirmed: Bool)
	{
		guard !hasCompletedDecision, let parent = sheetParent
		else
		{
			return
		}
		hasCompletedDecision = true
		parent.endSheet(
			self,
			returnCode: confirmed ? .OK : .cancel
		)
	}
}
