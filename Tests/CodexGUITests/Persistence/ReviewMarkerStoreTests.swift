import Foundation
import Testing

@testable import CodexGUI

struct ReviewMarkerStoreTests
{
	@Test func reviewMarkerInvalidatesOnlyWhenReferencedContentChanges() throws
	{
		let suite = "ReviewModelsTests.\(UUID())"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let store = ReviewMarkerStore(defaults: defaults)
		let first = try ReviewModelTestFixture.reviewFile(diff: "@@ -1 +1 @@\n-old\n+new")
		let changed = try ReviewModelTestFixture.reviewFile(diff: "@@ -1 +1 @@\n-old\n+newer")
		let reference = ReviewReference(
			threadID: "thread",
			turnID: "turn",
			file: first
		)

		store.setReviewed(
			true,
			projectPath: "/project",
			reference: reference,
			fingerprint: first.fingerprint
		)
		#expect(
			store.isReviewed(
				projectPath: "/project",
				reference: reference,
				fingerprint: first.fingerprint
			)
		)
		#expect(
			!store.isReviewed(
				projectPath: "/project",
				reference: reference,
				fingerprint: changed.fingerprint
			)
		)
		#expect(
			!store.isReviewed(
				projectPath: "/another",
				reference: reference,
				fingerprint: first.fingerprint
			)
		)
		let restored = ReviewMarkerStore(defaults: defaults)
		#expect(
			restored.isReviewed(
				projectPath: "/project",
				reference: reference,
				fingerprint: first.fingerprint
			)
		)
	}

}
