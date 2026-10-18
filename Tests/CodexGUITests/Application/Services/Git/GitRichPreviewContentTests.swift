import Darwin
import Foundation
import Testing

@testable import CodexGUI

struct GitRichPreviewContentTests
{
	@Test func unstoredTargetMatchesSnapshotAndRejectsLaterEdits() async throws
	{
		let fixture = try GitTurnBaselineFixture()
		defer
		{
			fixture.remove()
		}
		try fixture.write(
			"preview.md",
			"# Before\n"
		)
		try fixture.git(["add", "preview.md"])
		try fixture.commit()
		try fixture.write(
			"preview.md",
			"# After\n"
		)
		let snapshot = try await compare(
			fixture,
			scope: .unstaged
		)
		let file = try #require(snapshot.files.first)
		let bytes = try await GitRichPreviewContent.read(
			file: file,
			snapshot: snapshot
		)
		#expect(bytes == Data("# After\n".utf8))
		try fixture.write(
			"preview.md",
			"# Later\n"
		)
		await #expect(throws: GitComparisonFailure.repositoryChanged)
		{
			try await GitRichPreviewContent.read(
				file: file,
				snapshot: snapshot
			)
		}
	}

	@Test func stagedPreviewUsesIndexAndDeletedPreviewUsesBase() async throws
	{
		let fixture = try GitTurnBaselineFixture()
		defer
		{
			fixture.remove()
		}
		try fixture.write(
			"preview.md",
			"# Before\n"
		)
		try fixture.git(["add", "preview.md"])
		try fixture.commit()
		try fixture.write(
			"preview.md",
			"# Staged\n"
		)
		try fixture.git(["add", "preview.md"])
		let staged = try await compare(
			fixture,
			scope: .staged
		)
		try fixture.write(
			"preview.md",
			"# Unstaged\n"
		)
		let stagedFile = try #require(staged.files.first)
		let bytes = try await GitRichPreviewContent.read(
			file: stagedFile,
			snapshot: staged
		)
		#expect(bytes == Data("# Staged\n".utf8))
		try fixture.git(["rm", "-f", "preview.md"])
		let deleted = try await compare(
			fixture,
			scope: .staged
		)
		let deletedFile = try #require(deleted.files.first)
		#expect(deletedFile.kind == .deleted)
		let base = try await GitRichPreviewContent.read(
			file: deletedFile,
			snapshot: deleted
		)
		#expect(base == Data("# Before\n".utf8))
	}

	@Test func symbolicLinksHaveNoPreviewBlob() async throws
	{
		let fixture = try GitTurnBaselineFixture()
		defer
		{
			fixture.remove()
		}
		try FileManager.default.createSymbolicLink(
			atPath: fixture.root.appendingPathComponent("link.md").path,
			withDestinationPath: "source.txt"
		)
		try fixture.git(["add", "link.md"])
		let snapshot = try await compare(
			fixture,
			scope: .staged
		)
		#expect(GitRichPreviewContent.blobID(for: try #require(snapshot.files.first)) == nil)
	}

	@Test(.timeLimit(.minutes(1)))
	func unstoredTargetRejectsReplacementWithANamedPipe() async throws
	{
		let fixture = try GitTurnBaselineFixture()
		defer
		{
			fixture.remove()
		}
		try fixture.write(
			"preview.md",
			"# Before\n"
		)
		try fixture.git(["add", "preview.md"])
		try fixture.commit()
		try fixture.write(
			"preview.md",
			"# Unstored target\n"
		)
		let snapshot = try await compare(
			fixture,
			scope: .unstaged
		)
		let file = try #require(snapshot.files.first)
		let path = fixture.root.appendingPathComponent("preview.md").path
		try FileManager.default.removeItem(atPath: path)
		try #require(mkfifo(
			path,
			0o600
		) == 0)
		await #expect(throws: GitComparisonFailure.repositoryChanged)
		{
			try await GitRichPreviewContent.read(
				file: file,
				snapshot: snapshot
			)
		}
	}

	private func compare(
		_ fixture: GitTurnBaselineFixture,
		scope: GitComparisonScope
	) async throws -> GitComparisonSnapshot
	{
		let owner = fixture.comparisonRequest(
			baseline: nil,
			turnID: nil
		).owner
		let request = GitComparisonRequest(
			owner: owner,
			repositoryRoot: fixture.root.path,
			scope: scope,
			generation: 1
		)
		let result = await LocalGitComparisonService().compare(request)
		guard case .snapshot(let snapshot) = result
		else
		{
			Issue.record("Comparison unavailable: \(result)")
			throw GitComparisonFailure.repositoryUnavailable
		}
		return snapshot
	}
}
