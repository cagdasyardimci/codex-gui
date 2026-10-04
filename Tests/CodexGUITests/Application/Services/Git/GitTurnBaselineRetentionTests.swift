import Foundation
import Testing

@testable import CodexGUI

struct GitTurnBaselineRetentionTests
{
	@Test func restoredMetadataUsesCanonicalEncodingAtTheExactByteLimit() async throws
	{
		let fixture = try GitTurnBaselineFixture()
		defer
		{
			fixture.remove()
		}
		for index in 0 ..< 16
		{
			try fixture.write(
				"é e\u{301} \"file\" \(index).txt",
				"content \(index)\n"
			)
		}
		try fixture.git(["add", "."])
		let initial = LocalGitTurnBaselineService(storageRoot: fixture.storageRoot)
		let pending = try await fixture.capture(initial)
		let turnID = "accepted \"turn\" \\ 雪 e\u{301}\u{2028}\u{2029}"
		let accepted = try await fixture.bind(
			pending,
			service: initial,
			turnID: turnID
		)
		let record = try savedRecord(
			accepted,
			fixture: fixture
		)
		let canonicalBytes = try JSONEncoder().encode(record).count
		let manifest = manifestURL(
			accepted,
			fixture: fixture
		)
		let prettyEncoder = JSONEncoder()
		prettyEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		let formatted = try prettyEncoder.encode(record)
		#expect(formatted.count > canonicalBytes)
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o600],
			ofItemAtPath: manifest.path
		)
		try formatted.write(to: manifest)
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o400],
			ofItemAtPath: manifest.path
		)

		var limits = GitTurnBaselineLimits()
		limits.maximumRetainedBytes = accepted.byteCount + canonicalBytes
		let exact = LocalGitTurnBaselineService(
			storageRoot: fixture.storageRoot,
			limits: limits
		)
		#expect(await exact.lookup(
			repositoryRoot: fixture.root.path,
			threadID: accepted.identity.threadID,
			turnID: turnID
		) == accepted)
		limits.maximumRetainedBytes -= 1
		let tooSmall = LocalGitTurnBaselineService(
			storageRoot: fixture.storageRoot,
			limits: limits
		)
		#expect(await tooSmall.lookup(
			repositoryRoot: fixture.root.path,
			threadID: accepted.identity.threadID,
			turnID: turnID
		) == nil)
		#expect(try storedIDs(fixture).isEmpty)
	}

	@Test func bindingRefreshesTheSizeForAnEscapedLongTurnID() async throws
	{
		let fixture = try GitTurnBaselineFixture()
		defer
		{
			fixture.remove()
		}
		let probe = LocalGitTurnBaselineService(storageRoot: fixture.storageRoot)
		let sample = try await fixture.capture(probe)
		let sampleRecord = try savedRecord(
			sample,
			fixture: fixture
		)
		let sampleBytes = try logicalBytes(sampleRecord)
		await probe.discard(sample)
		var limits = GitTurnBaselineLimits()
		limits.maximumRetainedBytes = sampleBytes + 128
		let service = LocalGitTurnBaselineService(
			storageRoot: fixture.storageRoot,
			limits: limits
		)
		let captured = try await fixture.capture(service)
		let before = try savedRecord(
			captured,
			fixture: fixture
		)
		#expect(try logicalBytes(before) <= limits.maximumRetainedBytes)
		let turnID = String(
			repeating: "\"\\雪\u{2028}",
			count: 512
		)
		var after = before
		after.reference = captured.bound(to: turnID)
		#expect(try logicalBytes(after) > limits.maximumRetainedBytes)
		let result = await service.bind(
			captured,
			turnID: turnID
		)
		guard case .unavailable(.lastTurnBaselineUnavailable) = result
		else
		{
			Issue.record("Binding must refresh canonical metadata bytes before retention.")
			return
		}
		#expect(await service.lookup(
			repositoryRoot: fixture.root.path,
			threadID: captured.identity.threadID,
			turnID: turnID
		) == nil)
		#expect(try storedIDs(fixture).isEmpty)
	}

	@Test func replacingAndDiscardingRecordsReleaseTheirRetainedBytes() async throws
	{
		let fixture = try GitTurnBaselineFixture()
		defer
		{
			fixture.remove()
		}
		try fixture.write(
			"source.txt",
			String(
				repeating: "x",
				count: 16 * 1024
			)
		)
		let initial = LocalGitTurnBaselineService(storageRoot: fixture.storageRoot)
		let first = try await captureAccepted(
			initial,
			fixture: fixture,
			thread: "first",
			turn: "old"
		)
		let second = try await captureAccepted(
			initial,
			fixture: fixture,
			thread: "other",
			turn: "kept"
		)
		let unitBytes = max(
			try logicalBytes(savedRecord(
				first,
				fixture: fixture
			)),
			try logicalBytes(savedRecord(
				second,
				fixture: fixture
			))
		)
		var limits = GitTurnBaselineLimits()
		limits.maximumRetainedBytes = 3 * unitBytes + 256
		let service = LocalGitTurnBaselineService(
			storageRoot: fixture.storageRoot,
			limits: limits
		)
		let replacement = try await captureAccepted(
			service,
			fixture: fixture,
			thread: "first",
			turn: "new"
		)
		#expect(await service.lookup(
			repositoryRoot: fixture.root.path,
			threadID: "first",
			turnID: "old"
		) == nil)
		let discarded = try await fixture.capture(
			service,
			threadID: "discarded"
		)
		await service.discard(discarded)
		let next = try await fixture.capture(
			service,
			threadID: "pending"
		)
		#expect(try storedIDs(fixture) == Set([
			replacement.identity.id.uuidString,
			second.identity.id.uuidString,
			next.identity.id.uuidString
		]))
		#expect(await service.lookup(
			repositoryRoot: fixture.root.path,
			threadID: "other",
			turnID: "kept"
		) == second)
	}

	@Test func restoringOverBudgetEvictsMultipleOldestRecords() async throws
	{
		let fixture = try GitTurnBaselineFixture()
		defer
		{
			fixture.remove()
		}
		try fixture.write(
			"source.txt",
			String(
				repeating: "x",
				count: 16 * 1024
			)
		)
		let initial = LocalGitTurnBaselineService(storageRoot: fixture.storageRoot)
		var references: [GitTurnBaselineReference] = []
		for index in 0 ..< 4
		{
			references.append(try await captureAccepted(
				initial,
				fixture: fixture,
				thread: "chat-\(index)",
				turn: "turn-\(index)"
			))
		}
		let newest = try #require(references.last)
		var limits = GitTurnBaselineLimits()
		limits.maximumRetainedBytes = try logicalBytes(savedRecord(
			newest,
			fixture: fixture
		))
		let service = LocalGitTurnBaselineService(
			storageRoot: fixture.storageRoot,
			limits: limits
		)
		#expect(await service.lookup(
			repositoryRoot: fixture.root.path,
			threadID: "chat-3",
			turnID: "turn-3"
		) == newest)
		for index in 0 ..< 3
		{
			#expect(await service.lookup(
				repositoryRoot: fixture.root.path,
				threadID: "chat-\(index)",
				turnID: "turn-\(index)"
			) == nil)
		}
		#expect(try storedIDs(fixture) == [newest.identity.id.uuidString])
	}

	@Test func retentionReadsCurrentRecordsAfterAnEvictionSuspends() async throws
	{
		let fixture = try GitTurnBaselineFixture()
		defer
		{
			fixture.remove()
		}
		try fixture.write(
			"source.txt",
			String(
				repeating: "x",
				count: 16 * 1024
			)
		)
		let initial = LocalGitTurnBaselineService(storageRoot: fixture.storageRoot)
		let first = try await captureAccepted(
			initial,
			fixture: fixture,
			thread: "first",
			turn: "turn"
		)
		let second = try await captureAccepted(
			initial,
			fixture: fixture,
			thread: "other",
			turn: "turn"
		)
		let third = try await captureAccepted(
			initial,
			fixture: fixture,
			thread: "third",
			turn: "turn"
		)
		let unitBytes = max(
			try logicalBytes(savedRecord(
				second,
				fixture: fixture
			)),
			try logicalBytes(savedRecord(
				third,
				fixture: fixture
			))
		)
		var limits = GitTurnBaselineLimits()
		limits.maximumRetainedBytes = 2 * unitBytes + 128
		let gate = BaselineRemovalGate()
		let root = fixture.storageRoot
		let removalLimits = limits
		let service = LocalGitTurnBaselineService(
			storageRoot: root,
			limits: limits,
			removeStoredRecord:
			{
				id in
				await gate.pauseFirstRemoval()
				await Task.detached
				{
					GitTurnBaselineStorage(
						root: root,
						limits: removalLimits
					).remove(id)
				}.value
			}
		)
		let restoring = Task
		{
			await service.lookup(
				repositoryRoot: fixture.root.path,
				threadID: "third",
				turnID: "turn"
			)
		}
		do
		{
			try #require(await gate.waitUntilPaused())
			await service.discard(second)
			let fourth = try await captureAccepted(
				service,
				fixture: fixture,
				thread: "fourth",
				turn: "turn"
			)
			await gate.release()
			#expect(await restoring.value == third)
			#expect(await service.lookup(
				repositoryRoot: fixture.root.path,
				threadID: "fourth",
				turnID: "turn"
			) == fourth)
			#expect(await service.lookup(
				repositoryRoot: fixture.root.path,
				threadID: "first",
				turnID: "turn"
			) == nil)
			#expect(try storedIDs(fixture) == Set([
				third.identity.id.uuidString,
				fourth.identity.id.uuidString
			]))
			#expect(first.capturedAt < third.capturedAt)
		}
		catch
		{
			await gate.release()
			_ = await restoring.value
			throw error
		}
	}

	private func captureAccepted(
		_ service: LocalGitTurnBaselineService,
		fixture: GitTurnBaselineFixture,
		thread: String,
		turn: String
	) async throws -> GitTurnBaselineReference
	{
		let captured = try await fixture.capture(
			service,
			threadID: thread
		)
		return try await fixture.bind(
			captured,
			service: service,
			turnID: turn
		)
	}

	private func manifestURL(
		_ reference: GitTurnBaselineReference,
		fixture: GitTurnBaselineFixture
	) -> URL
	{
		fixture.storageRoot.appendingPathComponent(reference.identity.id.uuidString)
			.appendingPathComponent("manifest.json")
	}

	private func savedRecord(
		_ reference: GitTurnBaselineReference,
		fixture: GitTurnBaselineFixture
	) throws -> GitTurnBaselineRecord
	{
		try JSONDecoder().decode(
			GitTurnBaselineRecord.self,
			from: Data(contentsOf: manifestURL(
				reference,
				fixture: fixture
			))
		)
	}

	private func logicalBytes(_ record: GitTurnBaselineRecord) throws -> Int
	{
		try JSONEncoder().encode(record).count + record.reference.byteCount
	}

	private func storedIDs(_ fixture: GitTurnBaselineFixture) throws -> Set<String>
	{
		Set(try FileManager.default.contentsOfDirectory(atPath: fixture.storageRoot.path))
	}
}

private actor BaselineRemovalGate
{
	private var paused = false
	private var released = false
	private var continuation: CheckedContinuation<Void, Never>?

	func pauseFirstRemoval() async
	{
		guard !paused
		else
		{
			return
		}
		paused = true
		guard !released
		else
		{
			return
		}
		await withCheckedContinuation
		{
			continuation = $0
		}
	}

	func release()
	{
		released = true
		continuation?.resume()
		continuation = nil
	}

	func waitUntilPaused() async -> Bool
	{
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: .seconds(5))
		while !paused, clock.now < deadline
		{
			guard !Task.isCancelled
			else
			{
				return false
			}
			try? await Task.sleep(for: .milliseconds(1))
		}
		return paused
	}
}
