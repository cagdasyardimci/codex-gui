import Foundation
import Testing

@testable import CodexGUI

struct GitTurnBaselinePatchNormalizerTests
{
	@Test func pathsOnlyLoseLeadingScratchComponentAndHunksKeepExactBytes()
	{
		let original = """
		diff --git a/after/dir/a/before/file b/after/dir/a/before/file
		new file mode 100644
		--- /dev/null
		+++ b/after/dir/a/before/file
		@@ -0,0 +1,3 @@
		+--- a/before/source
		+rename from before/source
		+Binary files a/before/content and b/after/content differ
		diff --git a/before/deleted b/before/deleted
		deleted file mode 100644
		--- a/before/deleted
		+++ /dev/null
		@@ -1 +0,0 @@
		-old
		"""
		let normalized = String(
			decoding: GitTurnBaselinePatchNormalizer.normalize(Data(original.utf8)),
			as: UTF8.self
		)
		#expect(normalized.contains("diff --git a/dir/a/before/file b/dir/a/before/file"))
		#expect(normalized.contains("+++ b/dir/a/before/file"))
		#expect(normalized.contains("diff --git a/deleted b/deleted"))
		#expect(normalized.contains("+--- a/before/source"))
		#expect(normalized.contains("+rename from before/source"))
		#expect(normalized.contains("+Binary files a/before/content and b/after/content differ"))
	}

	@Test func binaryAddedAndDeletedMarkersRetainNullSide()
	{
		let original = "diff --git a/after/new.bin b/after/new.bin\nnew file mode 100644\n"
			+ "Binary files /dev/null and b/after/new.bin differ\n"
			+ "diff --git a/before/old.bin b/before/old.bin\ndeleted file mode 100644\n"
			+ "Binary files a/before/old.bin and /dev/null differ\n"
		let normalized = String(
			decoding: GitTurnBaselinePatchNormalizer.normalize(Data(original.utf8)),
			as: UTF8.self
		)
		#expect(normalized.contains("diff --git a/new.bin b/new.bin"))
		#expect(normalized.contains("Binary files /dev/null and b/new.bin differ"))
		#expect(normalized.contains("diff --git a/old.bin b/old.bin"))
		#expect(normalized.contains("Binary files a/old.bin and /dev/null differ"))
	}

	@Test func quotedRenamePathsAndSourceBytesSurvive()
	{
		let original = "diff --git \"a/before/old\\tname\" \"b/after/new\\tname\"\n"
			+ "similarity index 100%\nrename from \"before/old\\tname\"\n"
			+ "rename to \"after/new\\tname\"\n"
		let normalized = GitTurnBaselinePatchNormalizer.normalize(Data(original.utf8))
		let file = GitComparisonPatchParser.files(in: normalized).first
		#expect(file?.oldPath == "old\tname")
		#expect(file?.newPath == "new\tname")
		#expect(file?.kind == .renamed)
	}

	@Test func typeChangesCoalescePathIdentityWithoutLosingCountsOrHunks() throws
	{
		let original = "diff --git a/before/leaf b/before/leaf\ndeleted file mode 120000\n"
			+ "--- a/before/leaf\n+++ /dev/null\n@@ -1 +0,0 @@\n-target\n"
			+ "diff --git a/after/leaf b/after/leaf\nnew file mode 100644\n"
			+ "--- /dev/null\n+++ b/after/leaf\n@@ -0,0 +1 @@\n+new source\n"
		let normalized = GitTurnBaselinePatchNormalizer.normalize(Data(original.utf8))
		let files = GitComparisonPatchParser.files(in: normalized)
		#expect(files.count == 1)
		let file = try #require(files.first)
		#expect(file.path == "leaf")
		#expect(file.kind == .modified)
		#expect(file.additions == 1 && file.deletions == 1)
		#expect(file.hunks.count == 2)
		#expect(file.patch.contains("+new source"))
		#expect(String(
			decoding: normalized,
			as: UTF8.self
		).components(separatedBy: "diff --git")
			.count == 3)
	}

	@Test func renamedReplacementKeepsItsOriginForNavigation() throws
	{
		let patch = "diff --git a/target b/target\ndeleted file mode 100644\n"
			+ "--- a/target\n+++ /dev/null\n@@ -1 +0,0 @@\n-replaced\n"
			+ "diff --git a/origin b/target\nsimilarity index 100%\n"
			+ "rename from origin\nrename to target\n"
		let files = GitComparisonPatchParser.files(in: Data(patch.utf8))
		#expect(files.count == 1)
		let file = try #require(files.first)
		#expect(file.oldPath == "origin")
		#expect(file.newPath == "target")
		#expect(file.kind == .renamed)
		#expect(file.deletions == 1)
	}

	@Test func ambiguousModeHeaderChoosesMatchingScratchPathsAndKeepsHunkBytes()
	{
		let header = "diff --git a/before/dir b/name b/after/dir b/name\n"
		var source = Data("@@ -1 +1 @@\n+".utf8)
		source.append(contentsOf: [0xff, 0x0a])
		var original = Data((header + "old mode 100644\nnew mode 100755\n").utf8)
		original.append(source)
		let normalized = GitTurnBaselinePatchNormalizer.normalize(original)
		#expect(normalized.starts(with: Data("diff --git a/dir b/name b/dir b/name\n".utf8)))
		#expect(normalized.suffix(source.count) == source)
	}
}
