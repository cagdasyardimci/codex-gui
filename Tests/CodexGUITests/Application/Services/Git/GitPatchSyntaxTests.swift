import Testing

@testable import CodexGUI

struct GitPatchSyntaxTests
{
	@Test func quotedFieldsDecodeUtf8OctalAndEscapedControls()
	{
		let header = #"diff --git "a/\303\247\tname" "b/\303\247\tname""#
		let fields = GitPatchSyntax.headerFields(header)
		#expect(fields?.old == "a/ç\tname")
		#expect(fields?.new == "b/ç\tname")
		#expect(GitPatchSyntax.decodedPath(#""unterminated"#) == nil)
		#expect(GitPatchSyntax.decodedPath(#""bad\777""#) == nil)
	}

	@Test func markersStripOnlyTheirOwnSideAndHonorNullAndTab()
	{
		#expect(GitPatchSyntax.markerPath(
			"a/folder/file\t",
			side: "a/"
		) == "folder/file")
		#expect(GitPatchSyntax.markerPath(
			"b/folder/file",
			side: "a/"
		) == "b/folder/file")
		#expect(GitPatchSyntax.markerPath(
			"/dev/null\t",
			side: "b/"
		) == nil)
		#expect(GitPatchSyntax.markerPath(
			#""/dev/null""#,
			side: "b/"
		) == "/dev/null")
		#expect(GitPatchSyntax.markerPath(
			#""b/line\nname""#,
			side: "b/"
		) == "line\nname")
	}

	@Test func candidateSplitsPreserveAmbiguityForConsumerPolicy()
	{
		let pairs = Array(GitPatchSyntax.unquotedHeaderCandidates(
			"diff --git a/dir b/name b/dir b/name"
		))
		#expect(pairs.count == 3)
		#expect(pairs.first?.old == "dir" && pairs.first?.new == "name b/dir b/name")
		#expect(pairs.dropFirst().first?.old == "dir b/name")
		#expect(pairs.dropFirst().first?.new == "dir b/name")
		#expect(Array(GitPatchSyntax.unquotedHeaderCandidates("diff --cc a/file")).isEmpty)
	}
}
