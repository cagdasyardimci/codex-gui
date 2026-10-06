import Foundation
import Testing

@testable import CodexGUI

struct ReviewMarkerStoreTests
{
	@Test func reviewMarkerInvalidatesOnlyWhenReferencedContentChanges() throws
	{
		let suite = "ReviewMarkerStoreTests.\(UUID())"
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

	@Test func sectionMarkerSurvivesAnUnrelatedSectionEdit() throws
	{
		let suite = "ReviewSectionMarkerTests.\(UUID())"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let store = ReviewMarkerStore(defaults: defaults)
		let unchangedSection = "@@ -1 +1 @@\n-old\n+new"
		let original = try ReviewModelTestFixture
			.reviewFile(diff: "\(unchangedSection)\n@@ -4 +4 @@\n-a\n+b")
		let revised = try ReviewModelTestFixture
			.reviewFile(diff: "\(unchangedSection)\n@@ -4 +4 @@\n-a\n+c")
		let firstHunk = try #require(original.hunks.first)
		let originalReference = ReviewReference(
			threadID: "thread",
			turnID: "turn",
			file: original,
			hunk: firstHunk
		)
		let sameHunk = try #require(revised.hunks.first)
		let revisedReference = ReviewReference(
			threadID: "thread",
			turnID: "turn",
			file: revised,
			hunk: sameHunk
		)

		store.setReviewed(
			true,
			projectPath: "/project",
			reference: originalReference,
			fingerprint: firstHunk.fingerprint
		)
		let changedOriginal = original.hunks[1]
		let changedRevised = revised.hunks[1]
		store.setReviewed(
			true,
			projectPath: "/project",
			reference: ReviewReference(
				threadID: "thread",
				turnID: "turn",
				file: original,
				hunk: changedOriginal
			),
			fingerprint: changedOriginal.fingerprint
		)
		#expect(original.fingerprint != revised.fingerprint)
		#expect(sameHunk.fingerprint == firstHunk.fingerprint)
		#expect(
			store.isReviewed(
				projectPath: "/project",
				reference: revisedReference,
				fingerprint: sameHunk.fingerprint
			)
		)
		#expect(
			!store.isReviewed(
				projectPath: "/project",
				reference: ReviewReference(
					threadID: "thread",
					turnID: "turn",
					file: revised,
					hunk: changedRevised
				),
				fingerprint: changedRevised.fingerprint
			)
		)
	}

	@Test func bulkReadsUseOneSnapshotAndPreserveFingerprintAndOriginRules() throws
	{
		let suite = "ReviewMarkerBulkTests.\(UUID())"
		let defaults = try #require(CountingReviewMarkerDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let store = ReviewMarkerStore(defaults: defaults)
		let file = try ReviewModelTestFixture.reviewFile(diff: "@@ -1 +1 @@\n-old\n+new")
		let hunk = try #require(file.hunks.first)
		let fileIdentity = ReviewMarkerIdentity(
			reference: ReviewReference(
				threadID: "thread",
				turnID: "turn",
				file: file
			),
			fingerprint: file.fingerprint
		)
		let hunkIdentity = ReviewMarkerIdentity(
			reference: ReviewReference(
				threadID: "thread",
				turnID: "turn",
				file: file,
				hunk: hunk
			),
			fingerprint: hunk.fingerprint
		)
		for identity in [fileIdentity, hunkIdentity]
		{
			store.setReviewed(
				true,
				projectPath: "/project",
				reference: identity.reference,
				fingerprint: identity.fingerprint
			)
		}
		let stale = ReviewMarkerIdentity(
			reference: fileIdentity.reference,
			fingerprint: "changed"
		)
		let otherTurn = ReviewMarkerIdentity(
			reference: ReviewReference(
				threadID: "thread",
				turnID: "other-turn",
				file: file
			),
			fingerprint: file.fingerprint
		)
		defaults.markerReadCount = 0
		let identities = [hunkIdentity, stale, fileIdentity, otherTurn, hunkIdentity]
		#expect(store.reviewedIdentities(
			projectPath: "/project",
			identities: identities
		) == [hunkIdentity, fileIdentity, hunkIdentity])
		#expect(defaults.markerReadCount == 1)
		#expect(store.reviewedIdentities(
			projectPath: "/another-project",
			identities: identities
		).isEmpty)
	}

	@Test func eachBulkReadObservesExternalDefaultsChanges() throws
	{
		let suite = "ReviewMarkerFreshnessTests.\(UUID())"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let file = try ReviewModelTestFixture.reviewFile(diff: "@@ -1 +1 @@\n-old\n+new")
		let identity = ReviewMarkerIdentity(
			reference: ReviewReference(
				threadID: "thread",
				turnID: "turn",
				file: file
			),
			fingerprint: file.fingerprint
		)
		let store = ReviewMarkerStore(defaults: defaults)
		#expect(store.reviewedIdentities(
			projectPath: "/project",
			identities: [identity]
		).isEmpty)
		let key = ["/project", "thread", "turn", file.path, ""].joined(separator: "\u{0}")
		defaults.set(
			[key: file.fingerprint],
			forKey: "reviewedChangeFingerprints.v1"
		)
		#expect(store.reviewedIdentities(
			projectPath: "/project",
			identities: [identity]
		) == [identity])
		defaults.removeObject(forKey: "reviewedChangeFingerprints.v1")
		#expect(store.reviewedIdentities(
			projectPath: "/project",
			identities: [identity]
		).isEmpty)
	}

}

private final class CountingReviewMarkerDefaults: UserDefaults, @unchecked Sendable
{
	var markerReadCount = 0

	override func dictionary(forKey defaultName: String) -> [String: Any]?
	{
		if defaultName == "reviewedChangeFingerprints.v1"
		{
			markerReadCount += 1
		}
		return super.dictionary(forKey: defaultName)
	}
}
