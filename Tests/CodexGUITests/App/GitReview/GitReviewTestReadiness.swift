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
	let request = try #require(
		controller.runtime.state.pendingRequest ?? controller.runtime.state.snapshot?.request
	)
	try #require(request.owner == owner)
	var completedSnapshot: GitComparisonSnapshot?
	for attempt in 0 ... 100
	{
		let state = controller.runtime.state
		if state.owner == owner, state.pendingRequest == nil,
			!state.isStale, state.failure == nil,
			let snapshot = state.snapshot, snapshot.request == request
		{
			completedSnapshot = snapshot
			break
		}
		if attempt < 100
		{
			await Task.yield()
		}
	}
	let snapshot = try #require(completedSnapshot)
	controller.view.layoutSubtreeIfNeeded()
	return snapshot
}
