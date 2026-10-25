import Foundation
import Testing

@testable import CodexGUI

struct GitComparisonPatchParserTests
{
	@Test func canonicallyEquivalentPathsDoNotCoalesceTheirHunksOrCounts() throws
	{
		let paths = ["Caf\u{E9}.swift", "Cafe\u{301}.swift"]
		let patches = paths.enumerated().map
		{
			index, path in
			"diff --git a/\(path) b/\(path)\n--- a/\(path)\n+++ b/\(path)\n"
				+ "@@ -1 +1 @@\n-old \(index)\n+new \(index)\n"
		}
		let files = GitComparisonPatchParser.files(in: Data(patches.joined().utf8))
		#expect(files.map
		{
			Data($0.path.utf8)
		} == paths.map
		{
			Data($0.utf8)
		})
		try #require(files.count == 2)
		for (index, file) in files.enumerated()
		{
			#expect(file.hunks.count == 1)
			#expect(file.additions == 1)
			#expect(file.deletions == 1)
			#expect(file.patch.contains("+new \(index)"))
			#expect(Data(file.patch.utf8).range(of: Data(("+++ b/" + paths[index]).utf8)) != nil)
		}
	}

	@Test func comparisonPreservesExactHunksAndCountsOnlyLFSeparatedBodies() throws
	{
		let metadata = "diff --git a/old.swift b/new.swift\nrename from old.swift\n"
			+ "rename to new.swift\n--- a/old.swift\n+++ b/new.swift\n"
		let first = "@@ -1,3 +2,3 @@\r\n context\r\n-old\r\n"
			+ "+new\u{2028}+literal\u{2029}-literal\r\n"
			+ "\\ No newline at end of file\n\n"
		let second = "@@ -10 +11,2 @@ second\n-rename to source\n"
			+ "+diff --git source\n+++ source marker\n\n"
		let patch = metadata + first + second
		let files = GitComparisonPatchParser.files(in: Data(patch.utf8))
		let file = try #require(files.first)
		#expect(files.count == 1)
		#expect(file.oldPath == "old.swift")
		#expect(file.newPath == "new.swift")
		#expect(file.kind == .renamed)
		#expect(file.patch.utf8.elementsEqual(patch.utf8))
		#expect(file.additions == 3)
		#expect(file.deletions == 2)
		#expect(file.hunks.count == 2)
		#expect(file.hunks[0].text.utf8.elementsEqual(first.dropLast().utf8))
		#expect(file.hunks[1].text.utf8.elementsEqual(second.utf8))
		#expect(file.hunks[0].oldStart == 1)
		#expect(file.hunks[0].newStart == 2)
		#expect(file.hunks[1].oldStart == 10)
		#expect(file.hunks[1].newStart == 11)
	}

	@Test func zeroLengthRangesKeepTheirHeaderPositions() throws
	{
		let ranges = [
			("@@ -0,0 +1 @@", "+created", 0, 1),
			("@@ -17,0 +18,2 @@", "+first\n+second", 17, 18),
			("@@ -1 +0,0 @@", "-removed", 1, 0),
			("@@ -17,2 +16,0 @@", "-first\n-second", 17, 16),
		]
		for (header, body, oldStart, newStart) in ranges
		{
			let hunkText = header + "\n" + body + "\n"
			let patch = "diff --git a/sample.txt b/sample.txt\n--- a/sample.txt\n"
				+ "+++ b/sample.txt\n" + hunkText
			let file = try #require(GitComparisonPatchParser.files(in: Data(patch.utf8)).first)
			let hunk = try #require(file.hunks.first)
			#expect(file.hunks.count == 1)
			#expect(hunk.oldStart == oldStart)
			#expect(hunk.newStart == newStart)
			#expect(hunk.header == header)
			#expect(hunk.text.utf8.elementsEqual(hunkText.utf8))
			#expect(file.patch.utf8.elementsEqual(patch.utf8))
		}
	}

	@Test func unsupportedSectionsKeepSeparateFileAndHunkBoundaries() throws
	{
		let first = "diff --git a/first b/first\n--- a/first\n+++ b/first\n"
			+ "@@ -1 +1 @@\n-old\n+new\n"
		let last = "diff --git a/last b/last\n--- a/last\n+++ b/last\n"
			+ "@@ -4 +5 @@\n+last\n"
		for unsupported in [
			"diff --cc conflict",
			"diff --combined conflict",
			"* Unmerged path conflict"
		]
		{
			let patch = first + unsupported + "\n@@@ -1 -1 +1 @@@\n++ignored\n" + last
			let files = GitComparisonPatchParser.files(in: Data(patch.utf8))
			#expect(files.map(\.path) == ["first", "last"])
			let firstFile = try #require(files.first)
			let lastFile = try #require(files.last)
			#expect(firstFile.patch.utf8.elementsEqual(first.dropLast().utf8))
			#expect(lastFile.patch.utf8.elementsEqual(last.utf8))
			#expect(firstFile.additions == 1)
			#expect(firstFile.deletions == 1)
			#expect(lastFile.additions == 1)
			#expect(lastFile.hunks.count == 1)
		}
	}

	@Test func typeChangesCoalesceAndMetadataOnlyFilesHaveNoChanges() throws
	{
		let deleted = "diff --git a/swapped b/swapped\ndeleted file mode 100644\n"
			+ "--- a/swapped\n+++ /dev/null\n@@ -1 +0,0 @@\n-regular\n"
		let added = "diff --git a/swapped b/swapped\nnew file mode 120000\n"
			+ "--- /dev/null\n+++ b/swapped\n@@ -0,0 +1 @@\n+target\n"
		let mode = "diff --git a/mode b/mode\nold mode 100644\nnew mode 100755\n"
		let binary = "diff --git \"a/tab\\tfile\" \"b/tab\\tfile\"\nGIT binary patch\n"
		let files = GitComparisonPatchParser.files(in: Data((deleted + added + mode + binary).utf8))
		#expect(files.map(\.path) == ["swapped", "mode", "tab\tfile"])
		let changed = try #require(files.first)
		#expect(changed.kind == .modified)
		#expect(changed.additions == 1)
		#expect(changed.deletions == 1)
		#expect(changed.hunks.count == 2)
		let coalesced = String(deleted.dropLast()) + "\n" + String(added.dropLast())
		#expect(changed.patch.utf8.elementsEqual(coalesced.utf8))
		#expect(files[1].hunks.isEmpty)
		#expect(files[1].additions == 0)
		#expect(files[1].deletions == 0)
		#expect(files[2].isBinary)
		#expect(files[2].hunks.isEmpty)
		#expect(files[2].additions == 0)
		#expect(files[2].deletions == 0)
	}

	@Test func parsesFullContextWithoutTreatingSourceAsMetadata() throws
	{
		let patch = """
		diff --git a/old.swift b/new.swift
		similarity index 75%
		rename from old.swift
		rename to new.swift
		--- a/old.swift
		+++ b/new.swift
		@@ -1,3 +1,3 @@
		 context
		-old
		+new
		 +++ source context
		"""
		let file = try #require(GitComparisonPatchParser.files(in: Data(patch.utf8)).first)
		#expect(file.oldPath == "old.swift")
		#expect(file.newPath == "new.swift")
		#expect(file.kind == .renamed)
		#expect(file.additions == 1)
		#expect(file.deletions == 1)
		#expect(file.hunks.first?.text.contains(" +++ source context") == true)
	}

	@Test func binaryAndQuotedPathMetadataRemainDistinct() throws
	{
		let patch = "diff --git \"a/tab\\tfile\" \"b/tab\\tfile\"\n"
			+ "Binary files \"a/tab\\tfile\" and \"b/tab\\tfile\" differ\n"
		let file = try #require(GitComparisonPatchParser.files(in: Data(patch.utf8)).first)
		#expect(file.isBinary)
		#expect(file.path == "tab\tfile")
		#expect(file.hunks.isEmpty)
	}

	@Test func markerSeparatorsDoNotDamageTabsInNames() throws
	{
		let quoted = "diff --git \"a/end\\t\" \"b/end\\t\"\n"
			+ "--- \"a/end\\t\"\n+++ \"b/end\\t\"\n@@ -1 +1 @@\n-a\n+b\n"
		let file = try #require(GitComparisonPatchParser.files(in: Data(quoted.utf8)).first)
		#expect(file.path == "end\t")
		let binary = "diff --git a/folder b/name b/folder b/name\n"
			+ "Binary files a/folder b/name and b/folder b/name differ\n"
		let binaryFile = try #require(GitComparisonPatchParser.files(in: Data(binary.utf8)).first)
		#expect(binaryFile.path == "folder b/name")
	}
}
