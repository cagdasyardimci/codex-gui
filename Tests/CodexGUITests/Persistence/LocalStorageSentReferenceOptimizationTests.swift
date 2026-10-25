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
