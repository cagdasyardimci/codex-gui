import Foundation

@testable import CodexGUI

/// Awaits this store's publication without a scheduling deadline.
@MainActor
func awaitWorkspaceSnapshot(
	_ store: WorkspaceStateStore,
	file: String = #fileID,
	line: Int = #line,
	matching predicate: @escaping @MainActor (ConversationSnapshot) -> Bool
) async
{
	let timing = TestTiming.begin(
		"workspace.readiness",
		detail: "\(file):\(line)"
	)
	defer
	{
		timing.end()
	}
	var observation: UUID?
	let stream = AsyncStream<Void>
	{
		continuation in
		var satisfied = false
		// Immediate observation also catches a fixture that is already ready.
		observation = store.observe
		{
			_ in
			guard !satisfied, predicate(store.currentSnapshot)
			else
			{
				return
			}
			satisfied = true
			timing.mark("satisfied")
			continuation.yield(())
			continuation.finish()
		}
	}
	// Cancellation retires the observation, including when a test's time limit is reached.
	for await _ in stream
	{
		break
	}
	timing.mark("resumed")
	if let observation
	{
		store.removeObserver(observation)
	}
}
