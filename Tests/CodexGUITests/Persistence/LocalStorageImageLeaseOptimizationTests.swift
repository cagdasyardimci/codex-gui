import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct LocalStorageImageLeaseOptimizationTests
{
	@Test func overlappingLeasesSkipPersistedReadsUntilTheLastRelease() async throws
	{
		let fixture = try await ImageLeaseStorageFixture()
		defer
		{
			fixture.cleanup()
		}
		let item = try await fixture.image()
		let first = fixture.storage.retainContextForRequest([item])
		let last = fixture.storage.retainContextForRequest([item.reused()])
		fixture.defaults.reads.removeAll()

		fixture.storage.releaseContextForRequest(first)
		#expect(fixture.defaults.reads["CodexGUI.draftContext", default: 0] == 0)
		#expect(fixture.defaults.reads["CodexGUI.sentReferences", default: 0] == 0)
		#expect(fixture.exists(item))
		fixture.storage.releaseContextForRequest(first)
		#expect(fixture.defaults.reads.isEmpty)

		fixture.storage.releaseContextForRequest(last)
		#expect(fixture.defaults.reads["CodexGUI.draftContext"] == 1)
		#expect(fixture.defaults.reads["CodexGUI.sentReferences"] == 1)
		#expect(!fixture.exists(item))
		fixture.storage.releaseContextForRequest(last)
		#expect(fixture.defaults.reads["CodexGUI.draftContext"] == 1)
		#expect(fixture.defaults.reads["CodexGUI.sentReferences"] == 1)
	}

	@Test func mixedCandidatesRespectLeasesFreshDraftsSentRecordsAndOwnedBoundaries() async throws
	{
		let fixture = try await ImageLeaseStorageFixture()
		defer
		{
			fixture.cleanup()
		}
		let pending = try await fixture.image()
		let draft = try await fixture.image()
		let sent = try await fixture.image()
		let discarded = try await fixture.image()
		let foreign = try await fixture.image(in: fixture.root)
		let userFile = try await fixture.image(filename: "user.png")
		let items = [pending, draft, sent, discarded, foreign, userFile]
		let batch = fixture.storage.retainContextForRequest(items)
		let remaining = fixture.storage.retainContextForRequest([pending.reused()])
		#expect(fixture.storage.draftContext(
			for: fixture.root,
			threadID: "draft"
		).isEmpty)
		#expect(fixture.storage.sentReferences(
			for: fixture.root,
			threadID: "sent"
		).isEmpty)
		let other = LocalStorage(
			defaults: fixture.defaults,
			imageStore: DraftImageStore(directory: fixture.imageDirectory)
		)
		other.saveDraftContext(
			[draft],
			for: fixture.root,
			threadID: "draft"
		)
		other.rememberSentReferences(
			[sent],
			for: fixture.root,
			threadID: "sent"
		)
		fixture.defaults.reads.removeAll()

		fixture.storage.releaseContextForRequest(batch)
		#expect(fixture.defaults.reads["CodexGUI.draftContext"] == 1)
		#expect(fixture.defaults.reads["CodexGUI.sentReferences"] == 1)
		#expect(fixture.exists(pending))
		#expect(fixture.exists(draft))
		#expect(fixture.exists(sent))
		#expect(!fixture.exists(discarded))
		#expect(fixture.exists(foreign))
		#expect(fixture.exists(userFile))

		fixture.storage.releaseContextForRequest(remaining)
		#expect(!fixture.exists(pending))
		#expect(fixture.exists(draft))
		#expect(fixture.exists(sent))
		#expect(fixture.exists(foreign))
		#expect(fixture.exists(userFile))
	}

	@Test(arguments: ["CodexGUI.draftContext", "CodexGUI.sentReferences"])
	func lastLeaseRefreshesExternalPersistedProtectionsAndTheirDeletion(key: String) async throws
	{
		let fixture = try await ImageLeaseStorageFixture()
		defer
		{
			fixture.cleanup()
		}
		let item = try await fixture.image()
		let request = fixture.storage.retainContextForRequest([item])
		#expect(fixture.storage.draftContext(
			for: fixture.root,
			threadID: "thread"
		).isEmpty)
		#expect(fixture.storage.sentReferences(
			for: fixture.root,
			threadID: "thread"
		).isEmpty)
		let otherDefaults = try #require(UserDefaults(suiteName: fixture.suite))
		let other = LocalStorage(
			defaults: otherDefaults,
			imageStore: DraftImageStore(directory: fixture.imageDirectory)
		)
		if key == "CodexGUI.draftContext"
		{
			other.saveDraftContext(
				[item],
				for: fixture.root,
				threadID: "thread"
			)
		}
		else
		{
			other.rememberSentReferences(
				[item],
				for: fixture.root,
				threadID: "thread"
			)
		}
		fixture.defaults.reads.removeAll()
		fixture.storage.releaseContextForRequest(request)
		#expect(fixture.defaults.reads["CodexGUI.draftContext"] == 1)
		#expect(fixture.defaults.reads["CodexGUI.sentReferences"] == 1)
		#expect(fixture.exists(item))

		otherDefaults.removeObject(forKey: key)
		let last = fixture.storage.retainContextForRequest([item])
		fixture.defaults.reads.removeAll()
		fixture.storage.releaseContextForRequest(last)
		#expect(fixture.defaults.reads["CodexGUI.draftContext"] == 1)
		#expect(fixture.defaults.reads["CodexGUI.sentReferences"] == 1)
		#expect(!fixture.exists(item))
	}

	@Test func remainingLeaseOwnershipIsResolvedAfterSymlinkRetargeting() async throws
	{
		let fixture = try await ImageLeaseStorageFixture()
		defer
		{
			fixture.cleanup()
		}
		let first = try await fixture.image()
		let second = try await fixture.image()
		let alias = fixture.root.appendingPathComponent("lease.png")
		try FileManager.default.createSymbolicLink(
			at: alias,
			withDestinationURL: URL(fileURLWithPath: try #require(first.path))
		)
		let aliasedItem = ComposerContextItem(
			kind: .image,
			title: "Leased alias",
			path: alias.path
		)
		let firstRequest = fixture.storage.retainContextForRequest([first])
		let aliasedRequest = fixture.storage.retainContextForRequest([aliasedItem])
		try FileManager.default.removeItem(at: alias)
		try FileManager.default.createSymbolicLink(
			at: alias,
			withDestinationURL: URL(fileURLWithPath: try #require(second.path))
		)

		fixture.storage.releaseContextForRequest(firstRequest)
		#expect(!fixture.exists(first))
		#expect(fixture.exists(second))
		fixture.storage.releaseContextForRequest(aliasedRequest)
		#expect(!fixture.exists(second))
	}

	@Test func foreignAndUserNamedImagesDoNotReadPersistedOwnershipOrGetDeleted() async throws
	{
		let fixture = try await ImageLeaseStorageFixture()
		defer
		{
			fixture.cleanup()
		}
		let foreign = try await fixture.image(in: fixture.root)
		let userFile = try await fixture.image(filename: "user.png")
		let request = fixture.storage.retainContextForRequest([foreign, userFile])
		fixture.defaults.reads.removeAll()
		fixture.storage.releaseContextForRequest(request)
		#expect(fixture.defaults.reads.isEmpty)
		#expect(fixture.exists(foreign))
		#expect(fixture.exists(userFile))
	}
}

@MainActor
private final class ImageLeaseStorageFixture
{
	let suite = "LocalStorageImageLeaseOptimizationTests.\(UUID())"
	let root = FileManager.default.temporaryDirectory
		.appendingPathComponent("ImageLeaseOptimization-\(UUID())")
	let imageDirectory: URL
	let defaults: ImageLeaseReadCountingDefaults
	let storage: LocalStorage

	init() async throws
	{
		let directory = root.appendingPathComponent("DraftImages")
		imageDirectory = directory
		try await BackgroundTestWork.perform
		{
			try FileManager.default.createDirectory(
				at: directory,
				withIntermediateDirectories: true
			)
		}
		defaults = try #require(ImageLeaseReadCountingDefaults(suiteName: suite))
		storage = LocalStorage(
			defaults: defaults,
			imageStore: DraftImageStore(directory: imageDirectory)
		)
	}

	func image(
		in directory: URL? = nil,
		filename: String = "\(UUID().uuidString).png"
	) async throws -> ComposerContextItem
	{
		let file = (directory ?? imageDirectory).appendingPathComponent(filename)
		try await BackgroundTestWork.perform
		{
			try Data([0x89, 0x50, 0x4E, 0x47]).write(to: file)
		}
		return ComposerContextItem(
			kind: .image,
			title: "Image",
			path: file.path
		)
	}

	func exists(_ item: ComposerContextItem) -> Bool
	{
		item.path.map
		{
			FileManager.default.fileExists(atPath: $0)
		} ?? false
	}

	func cleanup()
	{
		defaults.removePersistentDomain(forName: suite)
		try? FileManager.default.removeItem(at: root)
	}
}

private final class ImageLeaseReadCountingDefaults: UserDefaults, @unchecked Sendable
{
	var reads: [String: Int] = [:]

	override func data(forKey defaultName: String) -> Data?
	{
		reads[defaultName, default: 0] += 1
		return super.data(forKey: defaultName)
	}
}
