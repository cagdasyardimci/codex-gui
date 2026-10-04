import Foundation
import Testing

@testable import CodexGUI

@MainActor
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

	@Test func cachedContextRefreshesWhenAnotherStorageInstanceChangesDefaults() throws
	{
		let suite = "LocalStorageDraftOptimizationTests.\(UUID())"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let first = LocalStorage(defaults: defaults)
		let second = LocalStorage(defaults: defaults)
		let project = URL(fileURLWithPath: "/tmp/draft-optimization")
		let a = [ComposerContextItem(
			kind: .fileReference,
			title: "A",
			path: "/tmp/a.swift"
		)]
		let b = [ComposerContextItem(
			kind: .fileReference,
			title: "B",
			path: "/tmp/b.swift"
		)]
		first.saveDraftContext(
			a,
			for: project,
			threadID: "a"
		)
		#expect(first.draftContext(
			for: project,
			threadID: "b"
		).isEmpty)
		second.saveDraftContext(
			b,
			for: project,
			threadID: "b"
		)
		#expect(first.draftContext(
			for: project,
			threadID: "b"
		) == b)
		first.saveDraftContext(
			[],
			for: project,
			threadID: "a"
		)
		#expect(second.draftContext(
			for: project,
			threadID: "a"
		).isEmpty)
		#expect(second.draftContext(
			for: project,
			threadID: "b"
		) == b)
	}

	@Test func canonicallyEquivalentEditsPreserveExactStoredUTF8() throws
	{
		let suite = "LocalStorageDraftOptimizationTests.\(UUID())"
		let defaults = try #require(DraftWriteCountingDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let storage = LocalStorage(defaults: defaults)
		let project = URL(fileURLWithPath: "/tmp/draft-optimization")
		let composed = "\u{00E9}"
		let decomposed = "e\u{0301}"
		#expect(composed == decomposed)
		func context(_ text: String) -> [ComposerContextItem]
		{
			[ComposerContextItem(
				id: text,
				kind: .textExcerpt,
				title: text,
				path: text,
				firstLine: 1,
				lastLine: 1,
				excerpt: text
			)]
		}
		defaults.writes.removeAll()
		storage.saveDraft(
			composed,
			for: project,
			threadID: "thread"
		)
		storage.saveDraftContext(
			context(composed),
			for: project,
			threadID: "thread"
		)
		storage.saveDraft(
			decomposed,
			for: project,
			threadID: "thread"
		)
		storage.saveDraftContext(
			context(decomposed),
			for: project,
			threadID: "thread"
		)
		let reopened = LocalStorage(defaults: defaults)
		#expect(reopened.draft(
			for: project,
			threadID: "thread"
		).utf8
			.elementsEqual(decomposed.utf8))
		let item = try #require(reopened.draftContext(
			for: project,
			threadID: "thread"
		).first)
		#expect(item.id.utf8.elementsEqual(decomposed.utf8))
		#expect(item.title.utf8.elementsEqual(decomposed.utf8))
		#expect(item.path?.utf8.elementsEqual(decomposed.utf8) == true)
		#expect(item.excerpt?.utf8.elementsEqual(decomposed.utf8) == true)
		#expect(defaults.writes["CodexGUI.drafts"] == 2)
		#expect(defaults.writes["CodexGUI.draftContext"] == 2)
	}

	@Test func cachedContextDoesNotHideAnExternalDeletionOrInvalidPayload() throws
	{
		let suite = "LocalStorageDraftOptimizationTests.\(UUID())"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let storage = LocalStorage(defaults: defaults)
		let project = URL(fileURLWithPath: "/tmp/draft-optimization")
		let context = [ComposerContextItem(
			kind: .fileReference,
			title: "A",
			path: "/tmp/a.swift"
		)]
		storage.saveDraftContext(
			context,
			for: project,
			threadID: "a"
		)
		defaults.removeObject(forKey: "CodexGUI.draftContext")
		#expect(storage.draftContext(
			for: project,
			threadID: "a"
		).isEmpty)
		storage.saveDraftContext(
			context,
			for: project,
			threadID: "a"
		)
		defaults.set(
			Data("invalid JSON".utf8),
			forKey: "CodexGUI.draftContext"
		)
		#expect(storage.draftContext(
			for: project,
			threadID: "a"
		).isEmpty)
		storage.saveDraftContext(
			context,
			for: project,
			threadID: "a"
		)
		#expect(LocalStorage(defaults: defaults)
			.draftContext(
				for: project,
				threadID: "a"
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
