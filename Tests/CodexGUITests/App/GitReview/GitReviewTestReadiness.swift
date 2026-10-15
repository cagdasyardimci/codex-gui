import AppKit
import Testing

@testable import CodexGUI

/// Waits for the request captured at entry, rather than accepting an older snapshot.
@MainActor
@discardableResult
func waitForGitReviewComparison(
	_ controller: GitChangesViewController,
	owner: FeaturePresentationOwner
) async throws -> GitComparisonSnapshot
{
	try Task.checkCancellation()
	let request = try #require(
		controller.runtime.state.pendingRequest ?? controller.runtime.state.snapshot?.request
	)
	try #require(request.owner == owner)
	let runtime = controller.runtime
	let originalObserver = runtime.onChange
	let terminal = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
	let deadline = Task
	{
		do
		{
			try await Task.sleep(for: .seconds(10))
			terminal.continuation.finish()
		}
		catch
		{
		}
	}
	defer
	{
		deadline.cancel()
		runtime.onChange = originalObserver
		terminal.continuation.finish()
	}
	// Subscribe to the captured request's terminal publication; yield counts depend on load.
	func finishIfTerminal()
	{
		if runtime.state.owner != owner || runtime.state.pendingRequest != request
		{
			terminal.continuation.yield(())
			terminal.continuation.finish()
		}
	}
	runtime.onChange =
	{
		state in
		originalObserver?(state)
		finishIfTerminal()
	}
	finishIfTerminal()
	var arrivals = terminal.stream.makeAsyncIterator()
	let arrival = await arrivals.next()
	try Task.checkCancellation()
	try #require(
		arrival != nil,
		"The captured Git comparison did not finish within 10 seconds"
	)
	let state = runtime.state
	try #require(state.owner == owner && state.pendingRequest == nil)
	try #require(!state.isStale && state.failure == nil)
	let snapshot = try #require(state.snapshot)
	try #require(snapshot.request == request)
	controller.view.layoutSubtreeIfNeeded()
	return snapshot
}
