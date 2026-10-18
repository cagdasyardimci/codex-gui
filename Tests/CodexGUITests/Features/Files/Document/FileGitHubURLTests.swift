import Foundation
import Testing

@testable import CodexGUI

@Suite(.timeLimit(.minutes(1)))
struct FileGitHubURLTests
{
	@Test
	func repositoryAndNestedBrowsingResolveTheSameEncodedFile() throws
	{
		let fixture = try FileReadSafetyFixture()
		defer
		{
			try? FileManager.default.removeItem(at: fixture.root)
		}
		let root = fixture.root.resolvingSymlinksInPath()
		let nested = root.appendingPathComponent("Sources/nested space")
		try FileManager.default.createDirectory(
			at: nested,
			withIntermediateDirectories: true
		)
		try Data("source".utf8).write(to: nested.appendingPathComponent("a #?%.swift"))
		for command in [
			["init"],
			["config", "user.name", "Fixture"],
			["config", "user.email", "fixture@example.invalid"],
			["remote", "add", "origin", "git@github.com:owner/repo.git"],
			["add", "."],
			["commit", "-m", "fixture"],
		]
		{
			let result = try GitTestCommandRunner.run(
				in: root,
				arguments: command
			)
			try #require(result.terminationStatus == 0)
		}
		let commitResult = try GitTestCommandRunner.run(
			in: root,
			arguments: ["rev-parse", "HEAD"]
		)
		let commit = String(
			decoding: commitResult.output,
			as: UTF8.self
		)
		.trimmingCharacters(in: .whitespacesAndNewlines)
		let expected = "https://github.com/owner/repo/blob/\(commit)/Sources/"
			+ "nested%20space/a%20%23%3F%25.swift"
		for location in [
			FileLocation(
				root: root.path,
				relativePath: "Sources/nested space/a #?%.swift"
			),
			FileLocation(
				root: root.appendingPathComponent("Sources").path,
				relativePath: "nested space/a #?%.swift"
			),
			FileLocation(
				root: nested.path,
				relativePath: "a #?%.swift"
			),
		]
		{
			#expect(try FileGitHubURL.resolve(location: location).absoluteString == expected)
		}
		#expect(throws: NSError.self)
		{
			_ = try FileGitHubURL.resolve(location: FileLocation(
				root: root.path,
				relativePath: "../outside.swift"
			))
		}
	}
}
