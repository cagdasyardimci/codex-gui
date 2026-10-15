import AppKit
import Testing

@testable import CodexGUI

@Suite(
	.serialized,
	.timeLimit(.minutes(1))
) @MainActor
struct GitReviewDesignBehaviorTests
{
	@Test func canonicalFileNavigationAndLayout() async throws
	{
		try await GitReviewDesignChecks().verifyCanonicalFileNavigationAndLayout()
	}

	@Test func responsiveDiffAndScopeRetainSelectionAndOptions() async throws
	{
		try await GitReviewDesignChecks().verifyResponsiveDiffAndScope()
	}

	@Test func darkReviewAppearanceKeepsUnifiedRowsReadable() async throws
	{
		try await GitReviewDesignChecks().verifyDarkReviewAppearanceAndRows()
	}

	@Test func focusedReviewHostRestoresWindowPanes() async throws
	{
		try await GitReviewDesignChecks().verifyFocusedReviewHost()
	}
}
