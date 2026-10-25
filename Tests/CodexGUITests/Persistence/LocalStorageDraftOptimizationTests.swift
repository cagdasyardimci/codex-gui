import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct LocalStorageDraftOptimizationTests
{
	@Test func unchangedDraftTextAndContextDoNotRewriteDefaults() throws
	{
		let suite = "LocalStorageDraftOptimizationTests.\(UUID())"
		let defaults = try #require(DraftWriteCountingDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let storage = LocalStorage(defaults: defaults)
		let project = URL(fileURLWithPath: "/tmp/draft-optimization")
		let context = [ComposerContextItem(
			kind: .fileReference,
			title: "Example",
			path: "/tmp/example.swift"
		)]
		defaults.writes.removeAll()
		storage.saveDraft(
			"first",
			for: project,
			threadID: "thread"
		)
		storage.saveDraftContext(
			context,
			for: project,
			threadID: "thread"
		)
		for _ in 0 ..< 40
		{
			storage.saveDraft(
				"first",
				for: project,
				threadID: "thread"
			)
			storage.saveDraftContext(
				context,
				for: project,
				threadID: "thread"
			)
		}
		storage.saveDraft(
			"later",
			for: project,
			threadID: "thread"
		)
		storage.saveDraftContext(
			context,
			for: project,
			threadID: "thread"
		)
		#expect(defaults.writes["CodexGUI.drafts"] == 2)
		#expect(defaults.writes["CodexGUI.draftContext"] == 1)
		#expect(LocalStorage(defaults: defaults).draft(
			for: project,
			threadID: "thread"
		) == "later")
		#expect(LocalStorage(defaults: defaults)
			.draftContext(
				for: project,
				threadID: "thread"
			) == context)
	}

}

private final class DraftWriteCountingDefaults: UserDefaults, @unchecked Sendable
{
	var writes: [String: Int] = [:]

	override func set(
		_ value: Any?,
		forKey defaultName: String
	)
	{
		writes[defaultName, default: 0] += 1
		super.set(
			value,
			forKey: defaultName
		)
	}
}
