import Foundation
import Testing

@testable import CodexGUI

struct GitDiffHunkScannerTests
{
	@Test func splitLineScannerMatchesFrozenStringParserAndCounts()
	{
		let bodies = [
			"",
			" context\n-old\n+new",
			"-old\r\n+new\r\n",
			"+first\u{2028}+literal\u{2029}-literal\n-last",
			"+é e\u{301} 雪 👩🏽‍💻\n",
			"+rename to source\n--- source\n+++ source\n diff --git source",
			"-old\n\\ No newline at end of file\n+new\n\\ No newline at end of file",
			" context\n\n\n",
			"diff --git a/next b/next\n--- a/next\n+++ b/next\n@@ -8 +9 @@\n+next",
			"@@ -4,2 +5,3 @@ second\n-old\n+new\n+another\n"
		]
		for body in bodies
		{
			for prefix in ["", "ignored\n", "diff --git a/x b/x\n--- a/x\n+++ b/x\n"]
			{
				for header in ["", "@@ -1 +1 @@\n", "@@ -1 +1 @@\r\n"]
				{
					let diff = prefix + header + body
					let expected = frozenHunks(in: diff)
					let parsed = GitDiffParser.hunks(in: diff.components(separatedBy: "\n"))
					let stringHunks = GitDiffParser.hunks(in: diff)
					#expect(parsed.hunks.count == expected.count)
					#expect(stringHunks.count == expected.count)
					for (actual, legacy) in zip(
						parsed.hunks,
						expected
					)
					{
						#expect(actual.header.utf8.elementsEqual(legacy.header.utf8))
						#expect(actual.text.utf8.elementsEqual(legacy.text.utf8))
					}
					for (actual, legacy) in zip(
						stringHunks,
						expected
					)
					{
						#expect(actual.text.utf8.elementsEqual(legacy.text.utf8))
					}
					let bodyLines = expected.flatMap
					{
						$0.text.components(separatedBy: "\n").dropFirst()
					}
					let additions = bodyLines.filter
					{
						$0.hasPrefix("+")
					}.count
					let deletions = bodyLines.filter
					{
						$0.hasPrefix("-")
					}.count
					#expect(parsed.additions == additions)
					#expect(parsed.deletions == deletions)
				}
			}
		}
	}

	@Test func literalSeparatorsAndTrailingBlankLinesRemainInsideTheHunk() throws
	{
		let header = "@@ -1 +1 @@\r"
		let text = header + "\n-old\r\n+new\u{2028}+source\u{2029}-source\r\n"
			+ "\\ No newline at end of file\n\n"
		let parsed = GitDiffParser.hunks(in: text.components(separatedBy: "\n"))
		let hunk = try #require(parsed.hunks.first)
		#expect(parsed.hunks.count == 1)
		#expect(hunk.header.utf8.elementsEqual(header.utf8))
		#expect(hunk.text.utf8.elementsEqual(text.utf8))
		#expect(parsed.additions == 1)
		#expect(parsed.deletions == 1)
	}

	/// The previous string implementation is retained as an independent equivalence oracle.
	private func frozenHunks(in diff: String) -> [(header: String, text: String)]
	{
		var result: [(header: String, text: String)] = []
		var header: String?
		var content: [String] = []
		func finish()
		{
			guard let current = header
			else
			{
				return
			}
			result.append((current, content.joined(separator: "\n")))
			header = nil
			content = []
		}
		for line in diff.components(separatedBy: "\n")
		{
			if line.hasPrefix("diff --git ")
			{
				finish()
			}
			if line.hasPrefix("@@ ")
			{
				finish()
				header = line
			}
			if header != nil
			{
				content.append(line)
			}
		}
		finish()
		return result
	}
}
