import Foundation
import Testing

@testable import CodexGUI

struct GitTurnBaselineTreeReaderTests
{
	@Test func repeatedContentVerificationComparesBothEntriesAndExactBytes() throws
	{
		let fixture = try GitTurnBaselineFixture()
		defer
		{
			fixture.remove()
		}
		let reader = GitTurnBaselineTreeReader(
			root: fixture.root.path,
			limits: GitTurnBaselineLimits()
		)
		let captured = try reader.read("source.txt")
		#expect(try reader.contentsMatch([captured]))
		let differentBytes = GitTurnBaselineContent(
			entry: captured.entry,
			bytes: Data("different".utf8)
		)
		#expect(try !reader.contentsMatch([differentBytes]))
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o755],
			ofItemAtPath: fixture.root
				.appendingPathComponent("source.txt").path
		)
		#expect(try !reader.contentsMatch([captured]))
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o644],
			ofItemAtPath: fixture.root
				.appendingPathComponent("source.txt").path
		)
		try fixture.write(
			"source.txt",
			"replacement\n"
		)
		#expect(try !reader.contentsMatch([captured]))
	}

	@Test func repeatedContentVerificationKeepsMissingFilesAndSymlinkTargetsDistinct() throws
	{
		let fixture = try GitTurnBaselineFixture()
		defer
		{
			fixture.remove()
		}
		let reader = GitTurnBaselineTreeReader(
			root: fixture.root.path,
			limits: GitTurnBaselineLimits()
		)
		let missing = try reader.read("missing.txt")
		let link = fixture.root.appendingPathComponent("link.txt")
		try FileManager.default.createSymbolicLink(
			atPath: link.path,
			withDestinationPath: "source.txt"
		)
		let capturedLink = try reader.read("link.txt")
		#expect(try reader.contentsMatch([missing, capturedLink]))
		try fixture.write(
			"missing.txt",
			"now present\n"
		)
		#expect(try !reader.contentsMatch([missing]))
		try FileManager.default.removeItem(at: link)
		try FileManager.default.createSymbolicLink(
			atPath: link.path,
			withDestinationPath: "missing.txt"
		)
		#expect(try !reader.contentsMatch([capturedLink]))
	}

	@Test func aContentMismatchDoesNotSkipLaterCaptureOrFileLimits() throws
	{
		let fixture = try GitTurnBaselineFixture()
		defer
		{
			fixture.remove()
		}
		try fixture.write(
			"source.txt",
			"one"
		)
		try fixture.write(
			"second.txt",
			"two"
		)
		var limits = GitTurnBaselineLimits()
		limits.maximumCaptureBytes = 6
		limits.maximumFileBytes = 4
		let reader = GitTurnBaselineTreeReader(
			root: fixture.root.path,
			limits: limits
		)
		let captured = try [reader.read("source.txt"), reader.read("second.txt")]
		#expect(try reader.contentsMatch(captured))
		try fixture.write(
			"source.txt",
			"ONE"
		)
		try fixture.write(
			"second.txt",
			"four"
		)
		#expect(throws: GitTurnBaselineReadError.self)
		{
			try reader.contentsMatch(captured)
		}
		try fixture.write(
			"second.txt",
			"five!"
		)
		#expect(throws: GitTurnBaselineReadError.self)
		{
			try reader.contentsMatch(captured)
		}
	}

	@Test func capturePreservesTrackedPathLimitsAndAdditionalPaths() throws
	{
		let fixture = try GitTurnBaselineFixture()
		defer
		{
			fixture.remove()
		}
		try fixture.write(
			"previously-tracked.txt",
			"retained from the earlier baseline\n"
		)
		let reader = GitTurnBaselineTreeReader(
			root: fixture.root.path,
			limits: GitTurnBaselineLimits()
		)
		let captured = try reader.capture(additionalPaths: ["previously-tracked.txt"])
		#expect(captured.files.map(\.entry.path) == ["previously-tracked.txt", "source.txt"])
		#expect(try reader.contentsMatch(captured.files))
		var limits = GitTurnBaselineLimits()
		limits.maximumPaths = 1
		let limited = GitTurnBaselineTreeReader(
			root: fixture.root.path,
			limits: limits
		)
		#expect(throws: GitTurnBaselineReadError.self)
		{
			try limited.capture(additionalPaths: ["previously-tracked.txt"])
		}
	}

	@Test func cancelledRepeatedVerificationRejectsEvenAnEmptyTree() async throws
	{
		let reader = GitTurnBaselineTreeReader(
			root: "/unused",
			limits: GitTurnBaselineLimits()
		)
		let task = Task.detached
		{
			withUnsafeCurrentTask
			{
				$0?.cancel()
			}
			return try reader.contentsMatch([])
		}
		do
		{
			_ = try await task.value
			Issue.record("An empty verification must retain cancellation admission.")
		}
		catch is CancellationError
		{
		}
	}
}
