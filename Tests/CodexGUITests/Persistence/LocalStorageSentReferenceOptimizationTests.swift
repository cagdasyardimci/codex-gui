import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct LocalStorageSentReferenceOptimizationTests
{
	@Test func missingEmptyAndCorruptRecordsSkipProjectResolution() throws
	{
		let fixture = try SentReferenceStorageFixture()
		defer
		{
			fixture.cleanup()
		}
		#expect(fixture.storage.sentReferences(
			for: fixture.project,
			threadID: "thread"
		).isEmpty)
		#expect(fixture.decoder.calls == 0)
		for data in [Data("[]".utf8), Data("invalid JSON".utf8)]
		{
			fixture.defaults.set(
				data,
				forKey: "CodexGUI.sentReferences"
			)
			#expect(fixture.storage.sentReferences(
				for: fixture.project,
				threadID: "thread"
			).isEmpty)
		}
		#expect(fixture.decoder.calls == 3)
		#expect(fixture.resolutions.count == 0)
	}

	@Test func unchangedPayloadDecodesOnceAndResolvesProjectOncePerRead() throws
	{
		let fixture = try SentReferenceStorageFixture()
		defer
		{
			fixture.cleanup()
		}
		let items = references(200)
		let records = items.enumerated().map
		{
			index, item in
			StoredSentReferenceFixture(
				projectPath: fixture.canonicalProjectPath,
				threadID: index < 100 ? "first" : "second",
				item: item
			)
		}
		fixture.defaults.set(
			try JSONEncoder().encode(records),
			forKey: "CodexGUI.sentReferences"
		)

		for _ in 0 ..< 40
		{
			#expect(fixture.storage.sentReferences(
				for: fixture.project,
				threadID: "first"
			) == Array(items.prefix(100)))
		}
		#expect(fixture.decoder.calls == 1)
		#expect(fixture.resolutions.count == 40)
		#expect(fixture.storage.sentReferences(
			for: fixture.project,
			threadID: "missing"
		).isEmpty)
		#expect(fixture.decoder.calls == 1)
		#expect(fixture.resolutions.count == 41)
	}

	@Test func ownWritesRefreshTheSnapshotAndOtherInstancesRemainVisible() throws
	{
		let fixture = try SentReferenceStorageFixture()
		defer
		{
			fixture.cleanup()
		}
		let otherDefaults = try #require(UserDefaults(suiteName: fixture.suite))
		let other = LocalStorage(defaults: otherDefaults)
		let items = references(3)
		fixture.storage.rememberSentReferences(
			[items[0]],
			for: fixture.project,
			threadID: "first"
		)
		#expect(fixture.storage.sentReferences(
			for: fixture.project,
			threadID: "first"
		) == [items[0]])
		#expect(fixture.decoder.calls == 0)

		other.rememberSentReferences(
			[items[1]],
			for: fixture.project,
			threadID: "first"
		)
		#expect(fixture.storage.sentReferences(
			for: fixture.project,
			threadID: "first"
		) == Array(items.prefix(2)))
		#expect(fixture.decoder.calls == 1)
		fixture.storage.rememberSentReferences(
			[items[2]],
			for: fixture.project,
			threadID: "second"
		)
		#expect(fixture.decoder.calls == 1)
		#expect(other.sentReferences(
			for: fixture.project,
			threadID: "first"
		) == Array(items.prefix(2)))
		#expect(other.sentReferences(
			for: fixture.project,
			threadID: "second"
		) == [items[2]])
		#expect(other.sentReferences(
			for: fixture.otherProject,
			threadID: "first"
		).isEmpty)
	}

	@Test func externalCanonicalEquivalentBytesRefreshLiteralIdentifiersAndContent() throws
	{
		let fixture = try SentReferenceStorageFixture()
		defer
		{
			fixture.cleanup()
		}
		let composed = "\u{00E9}"
		let decomposed = "e\u{0301}"
		#expect(composed == decomposed)
		var retainedItems: [ComposerContextItem] = []
		for text in [composed, decomposed]
		{
			let item = ComposerContextItem(
				id: text,
				kind: .textExcerpt,
				title: text,
				path: text,
				firstLine: 1,
				lastLine: 2,
				excerpt: text
			)
			let record = StoredSentReferenceFixture(
				projectPath: fixture.canonicalProjectPath,
				threadID: text,
				item: item
			)
			fixture.defaults.set(
				try JSONEncoder().encode([record]),
				forKey: "CodexGUI.sentReferences"
			)
			let result = try #require(fixture.storage.sentReferences(
				for: fixture.project,
				threadID: text
			).first)
			#expect(result.id.utf8.elementsEqual(text.utf8))
			#expect(result.title.utf8.elementsEqual(text.utf8))
			#expect(result.path?.utf8.elementsEqual(text.utf8) == true)
			#expect(result.excerpt?.utf8.elementsEqual(text.utf8) == true)
			retainedItems.append(result)
		}
		#expect(fixture.decoder.calls == 2)
		#expect(retainedItems[0].id.utf8.elementsEqual(composed.utf8))
		let data = try #require(fixture.defaults.data(forKey: "CodexGUI.sentReferences"))
		let stored = try JSONDecoder().decode(
			[StoredSentReferenceFixture].self,
			from: data
		)
		#expect(stored.first?.threadID.utf8.elementsEqual(decomposed.utf8) == true)
		fixture.defaults.set(
			Data([0x20]) + data,
			forKey: "CodexGUI.sentReferences"
		)
		#expect(fixture.storage.sentReferences(
			for: fixture.project,
			threadID: decomposed
		).count == 1)
		#expect(fixture.decoder.calls == 3)
	}

	@Test func deletedCorruptAndWrongTypedPayloadsNeverReturnCachedRecords() throws
	{
		let fixture = try SentReferenceStorageFixture()
		defer
		{
			fixture.cleanup()
		}
		let item = try #require(references(1).first)
		let data = try JSONEncoder().encode([StoredSentReferenceFixture(
			projectPath: fixture.canonicalProjectPath,
			threadID: "thread",
			item: item
		)])
		fixture.defaults.set(
			data,
			forKey: "CodexGUI.sentReferences"
		)
		#expect(fixture.storage.sentReferences(
			for: fixture.project,
			threadID: "thread"
		) == [item])
		fixture.defaults.removeObject(forKey: "CodexGUI.sentReferences")
		#expect(fixture.storage.sentReferences(
			for: fixture.project,
			threadID: "thread"
		).isEmpty)
		#expect(fixture.decoder.calls == 1)

		fixture.defaults.set(
			Data("invalid JSON".utf8),
			forKey: "CodexGUI.sentReferences"
		)
		for _ in 0 ..< 3
		{
			#expect(fixture.storage.sentReferences(
				for: fixture.project,
				threadID: "thread"
			).isEmpty)
		}
		#expect(fixture.decoder.calls == 3)
		fixture.defaults.set(
			"wrong type",
			forKey: "CodexGUI.sentReferences"
		)
		#expect(fixture.storage.sentReferences(
			for: fixture.project,
			threadID: "thread"
		).isEmpty)
		#expect(fixture.decoder.calls == 3)
		fixture.defaults.set(
			data,
			forKey: "CodexGUI.sentReferences"
		)
		#expect(fixture.storage.sentReferences(
			for: fixture.project,
			threadID: "thread"
		) == [item])
		#expect(fixture.decoder.calls == 4)
	}

	@Test func legacyConversionIsCachedWithoutWritingUntilAnAppend() throws
	{
		let fixture = try SentReferenceStorageFixture()
		defer
		{
			fixture.cleanup()
		}
		let items = references(4)
		let otherPath = fixture.otherProject.standardizedFileURL.resolvingSymlinksInPath().path
		// Keep the stored schema independent of ComposerContextItem's current encoder.
		let legacyItems: [[String: Any]] = [
			["id": "item-0", "kind": "fileReference", "title": "item 0", "path": "File0.swift"],
			["id": "item-1", "kind": "fileReference", "title": "item 1", "path": "File1.swift"],
			["id": "item-2", "kind": "fileReference", "title": "item 2", "path": "File2.swift"],
			["id": "item-3", "kind": "fileReference", "title": "item 3", "path": "File3.swift"]
		]
		let legacy = [
			fixture.canonicalProjectPath: [
				"thread:second": [legacyItems[1]],
				"thread:first": [legacyItems[0]],
				"new-chat": [legacyItems[3]],
			],
			otherPath: ["thread:other": [legacyItems[2]]],
		]
		let originalData = try JSONSerialization.data(withJSONObject: legacy)
		fixture.defaults.set(
			originalData,
			forKey: "CodexGUI.sentReferences"
		)
		for _ in 0 ..< 3
		{
			#expect(fixture.storage.sentReferences(
				for: fixture.project,
				threadID: "first"
			) == [items[0]])
		}
		#expect(fixture.decoder.calls == 2)
		#expect(fixture.defaults.data(forKey: "CodexGUI.sentReferences") == originalData)
		fixture.storage.rememberSentReferences(
			[items[3]],
			for: fixture.project,
			threadID: "first"
		)
		#expect(fixture.decoder.calls == 2)
		let migratedData = try #require(fixture.defaults.data(forKey: "CodexGUI.sentReferences"))
		let records = try JSONDecoder().decode(
			[StoredSentReferenceFixture].self,
			from: migratedData
		)
		let orderedProjects = [fixture.canonicalProjectPath, otherPath].sorted()
		let expectedItems = orderedProjects.flatMap
		{
			$0 == fixture.canonicalProjectPath ? [items[0], items[1]] : [items[2]]
		} + [items[3]]
		#expect(records.map(\.item) == expectedItems)
		let migratedRecords = try #require(
			JSONSerialization.jsonObject(with: migratedData) as? [[String: Any]]
		)
		let expectedMigratedRecords: [[String: Any]] = orderedProjects.flatMap
		{
			projectPath -> [[String: Any]] in
			if projectPath == fixture.canonicalProjectPath
			{
				return [
					["projectPath": projectPath, "threadID": "first", "item": legacyItems[0]],
					["projectPath": projectPath, "threadID": "second", "item": legacyItems[1]]
				]
			}
			return [["projectPath": projectPath, "threadID": "other", "item": legacyItems[2]]]
		} + [[
			"projectPath": fixture.canonicalProjectPath,
			"threadID": "first",
			"item": legacyItems[3]
		]]
		#expect(NSArray(array: migratedRecords) == NSArray(array: expectedMigratedRecords))
		#expect(fixture.storage.sentReferences(
			for: fixture.project,
			threadID: "first"
		) == [items[0], items[3]])
	}

	@Test func projectSymlinkRetargetingIsResolvedOnEveryLookup() throws
	{
		let fixture = try SentReferenceStorageFixture()
		defer
		{
			fixture.cleanup()
		}
		for directory in [fixture.project, fixture.otherProject]
		{
			try FileManager.default.createDirectory(
				at: directory,
				withIntermediateDirectories: true
			)
		}
		let alias = fixture.root.appendingPathComponent("checkout")
		try FileManager.default.createSymbolicLink(
			at: alias,
			withDestinationURL: fixture.project
		)
		let items = references(2)
		fixture.storage.rememberSentReferences(
			[items[0]],
			for: alias,
			threadID: "thread"
		)
		fixture.storage.rememberSentReferences(
			[items[1]],
			for: fixture.otherProject,
			threadID: "thread"
		)
		fixture.resolutions.count = 0
		#expect(fixture.storage.sentReferences(
			for: alias,
			threadID: "thread"
		) == [items[0]])
		try FileManager.default.removeItem(at: alias)
		try FileManager.default.createSymbolicLink(
			at: alias,
			withDestinationURL: fixture.otherProject
		)
		#expect(fixture.storage.sentReferences(
			for: alias,
			threadID: "thread"
		) == [items[1]])
		#expect(fixture.resolutions.count == 2)
		#expect(fixture.decoder.calls == 0)
	}

	@Test func warmSnapshotPreservesGlobalPerThreadAndImageRetentionOrder() throws
	{
		let fixture = try SentReferenceStorageFixture()
		defer
		{
			fixture.cleanup()
		}
		let first = references(150)
		let second = references(
			150,
			prefix: "second"
		)
		let images = (0 ..< 30).map
		{
			ComposerContextItem(
				id: "image-\($0)",
				kind: .image,
				title: "Image \($0)"
			)
		}
		fixture.storage.rememberSentReferences(
			first,
			for: fixture.project,
			threadID: "first"
		)
		fixture.storage.rememberSentReferences(
			second,
			for: fixture.otherProject,
			threadID: "second"
		)
		fixture.storage.rememberSentReferences(
			images,
			for: fixture.project,
			threadID: "images"
		)
		for storage in [fixture.storage, LocalStorage(defaults: fixture.defaults)]
		{
			#expect(storage.sentReferences(
				for: fixture.project,
				threadID: "first"
			) == Array(first.suffix(76)))
			#expect(storage.sentReferences(
				for: fixture.otherProject,
				threadID: "second"
			) == Array(second.suffix(100)))
			#expect(storage.sentReferences(
				for: fixture.project,
				threadID: "images"
			) == Array(images.suffix(24)))
		}
		#expect(fixture.decoder.calls == 0)
	}

	private func references(
		_ count: Int,
		prefix: String = "item"
	) -> [ComposerContextItem]
	{
		(0 ..< count).map
		{
			ComposerContextItem(
				id: "\(prefix)-\($0)",
				kind: .fileReference,
				title: "\(prefix) \($0)",
				path: "File\($0).swift"
			)
		}
	}
}

private struct StoredSentReferenceFixture: Codable
{
	let projectPath: String
	let threadID: String
	let item: ComposerContextItem
}

@MainActor
private final class SentReferenceStorageFixture
{
	let suite = "LocalStorageSentReferenceOptimizationTests.\(UUID())"
	let root = FileManager.default.temporaryDirectory
		.appendingPathComponent("SentReferenceOptimization-\(UUID())")
	let defaults: UserDefaults
	let decoder = CountingSentReferenceDecoder()
	let resolutions = SentReferenceResolutionCounter()
	let storage: LocalStorage
	var project: URL
	{
		root.appendingPathComponent("project")
	}
	var otherProject: URL
	{
		root.appendingPathComponent("other")
	}
	var canonicalProjectPath: String
	{
		project.standardizedFileURL.resolvingSymlinksInPath().path
	}

	init() throws
	{
		defaults = try #require(UserDefaults(suiteName: suite))
		let resolutions = resolutions
		storage = LocalStorage(
			defaults: defaults,
			sentReferenceDecoder: decoder,
			resolveProjectPath:
			{
				resolutions.count += 1
				return $0.standardizedFileURL.resolvingSymlinksInPath().path
			}
		)
	}

	func cleanup()
	{
		defaults.removePersistentDomain(forName: suite)
		try? FileManager.default.removeItem(at: root)
	}
}

private final class SentReferenceResolutionCounter
{
	var count = 0
}

private final class CountingSentReferenceDecoder: JSONDecoder, @unchecked Sendable
{
	var calls = 0

	override func decode<T: Decodable>(
		_ type: T.Type,
		from data: Data
	) throws -> T
	{
		calls += 1
		return try super.decode(
			type,
			from: data
		)
	}
}
