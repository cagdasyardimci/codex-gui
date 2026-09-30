import Testing

@testable import CodexGUI

@Suite @MainActor
struct GitDiffParserTests
{
	@Test func relevantLineUsesNewSideAndDeletionFallback()
	{
		let added = """
		diff --git a/file.swift b/file.swift
		--- a/file.swift
		+++ b/file.swift
		@@ -8,3 +8,4 @@
		 context
		-old
		+new
		"""
		#expect(GitDiffParser.relevantLine(in: added) == 9)

		let deleted = """
		@@ -20,1 +20,0 @@
		-removed
		"""
		#expect(GitDiffParser.relevantLine(in: deleted) == 20)
		#expect(GitDiffParser.relevantLine(in: "no hunks") == nil)
	}

	@Test func selectedDiffMatchesExactSyntheticPathsIncludingSpaces()
	{
		let aggregate = """
		diff --git a/src/file b/src/file
		@@ -1 +1 @@
		-old
		+first
		diff --git a/src/file-extra b/src/file-extra
		@@ -1 +1 @@
		-old
		+wrong
		diff --git a/Folder Name/My File.swift b/Folder Name/My File.swift
		@@ -7 +7 @@
		-old
		+space
		"""

		#expect(GitDiffParser.selectedDiff(
			for: "src/file",
			in: aggregate
		).contains("+first"))
		#expect(!GitDiffParser.selectedDiff(
			for: "src/file",
			in: aggregate
		).contains("+wrong"))
		#expect(
			GitDiffParser.selectedDiff(
				for: "Folder Name/My File.swift",
				in: aggregate
			)
			.contains("+space")
		)
	}

	@Test func selectedDiffKeepsStandaloneHunkAndPrefersRenamedDestination()
	{
		let standalone = """
		@@ -2 +2 @@
		-old
		+new
		"""
		#expect(GitDiffParser.selectedDiff(
			for: "file",
			in: standalone
		) == standalone)

		let renamed = """
		diff --git a/old name b/new name
		rename from old name
		rename to new name
		--- a/old name
		+++ b/new name
		@@ -1 +1 @@
		-old
		+new
		"""
		#expect(GitDiffParser.selectedDiff(
			for: "new name",
			in: renamed
		).contains("+new"))
	}

	@Test func quotedUnicodePathsAndDiffLikeContentKeepFileIdentity()
	{
		let diff = #"""
		diff --git "a/\303\247.swift" "b/\303\247.swift"
		--- "a/\303\247.swift"
		+++ "b/\303\247.swift"
		@@ -3 +3,2 @@
		-old
		+let marker = "diff --git a/other b/other"
		+++ b/forged
		"""#
		#expect(GitDiffParser.selectedDiff(
			for: "ç.swift",
			in: diff
		) == diff)
		#expect(GitDiffParser.selectedDiff(
			for: "forged",
			in: diff
		).isEmpty)
		#expect(GitDiffParser.relevantLine(in: diff) == 3)
	}

	@Test func sharedParserDecodesRenameDeletionAndSyntheticPaths()
	{
		let diff = #"""
		diff --git "a/old\303\247.swift" "b/\303\247.swift"
		rename from "old\303\247.swift"
		rename to "\303\247.swift"
		--- "a/old\303\247.swift"
		+++ "b/\303\247.swift"
		@@ -1 +1 @@
		-old
		+new
		diff --git a/Folder Name/My File.swift b/Folder Name/My File.swift
		@@ -2 +2 @@
		-old
		+space
		diff --git "a/deleted\303\247.swift" "b/deleted\303\247.swift"
		deleted file mode 100644
		--- "a/deleted\303\247.swift"
		+++ /dev/null
		@@ -1 +0,0 @@
		-gone
		"""#
		#expect(
			GitDiffParser.filePaths(in: diff) == [
				"ç.swift",
				"Folder Name/My File.swift",
				"deletedç.swift",
			]
		)
		let renamed = GitDiffParser.selectedDiff(
			for: "ç.swift",
			in: diff
		)
		#expect(renamed.contains("+new"))
		#expect(!renamed.contains("+space"))
		#expect(GitDiffParser.renamePaths(in: renamed).old == "oldç.swift")
		#expect(GitDiffParser.renamePaths(in: renamed).new == "ç.swift")
		#expect(GitDiffParser.selectedDiff(
			for: "deletedç.swift",
			in: diff
		).contains("-gone"))
	}

	@Test func repeatedFileSectionsKeepTheirBoundaryAndIgnoreHunkContentAsMetadata()
	{
		let diff = """
		diff --git a/file.swift b/file.swift
		@@ -1 +1 @@
		-old
		+first
		diff --git a/file.swift b/file.swift
		@@ -8 +8 @@
		-old
		+second
		+rename to forged.swift
		"""
		let selected = GitDiffParser.selectedDiff(
			for: "file.swift",
			in: diff
		)
		#expect(selected.contains("+first\ndiff --git a/file.swift b/file.swift"))
		#expect(GitDiffParser.filePaths(in: diff) == ["file.swift"])
		#expect(GitDiffParser.renamePaths(in: diff).new == nil)
		let hunks = GitDiffParser.hunks(in: selected)
		#expect(hunks.count == 2)
		#expect(!hunks[0].text.contains("diff --git"))
		#expect(!hunks[0].text.contains("+second"))
	}
}
