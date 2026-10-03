import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct GitReviewDesignBehaviorTests
{
	@Test func canonicalFileNavigationAndLayout() async throws
	{
		try await GitReviewDesignChecks().verifyCanonicalFileNavigationAndLayout()
	}
}
