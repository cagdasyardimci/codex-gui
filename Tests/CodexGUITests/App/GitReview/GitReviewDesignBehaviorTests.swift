import AppKit
import Testing

@testable import CodexGUI

@Suite(
	.serialized,
	.timeLimit(.minutes(1))
) @MainActor
struct GitReviewDesignBehaviorTests
{

	@Test func responsiveDiffAndScopeRetainSelectionAndOptions() async throws
	{
		try await GitReviewDesignChecks().verifyResponsiveDiffAndScope()
	}

}
