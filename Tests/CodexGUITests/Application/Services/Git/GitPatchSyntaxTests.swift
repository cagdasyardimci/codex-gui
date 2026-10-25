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
		#expect(GitPatchSyntax.decodedPath(#""line\rquote\"slash\\é""#)
			== "line\rquote\"slash\\é")
		#expect(GitPatchSyntax.decodedPath(#""\1\12\1234""#) == "\u{1}\nS4")
		#expect(GitPatchSyntax.decodedPath(#""unterminated"#) == nil)
		#expect(GitPatchSyntax.decodedPath(#""bad\777""#) == nil)
		#expect(GitPatchSyntax.decodedPath("\"trailing\\") == nil)
		#expect(GitPatchSyntax.headerFields("diff --cc a/file b/file") == nil)
		#expect(GitPatchSyntax.headerFields("diff --git a/file") == nil)
		#expect(GitPatchSyntax.headerFields(#"diff --git a/file "unterminated"#) == nil)
		let mixed = GitPatchSyntax.headerFields(#"diff --git a/Old "b/New\rName""#)
		#expect(mixed?.old == "a/Old")
		#expect(mixed?.new == "b/New\rName")
	}

	@Test func markersStripOnlyTheirOwnSideAndHonorNullAndTab()
	{
		#expect(GitPatchSyntax.decodedField("folder/file\t") == "folder/file")
		#expect(GitPatchSyntax.decodedField("folder/with space") == "folder/with space")
		#expect(GitPatchSyntax.decodedField(#""folder/end\t""#) == "folder/end\t")
		#expect(GitPatchSyntax.decodedField(#""unterminated"#) == nil)
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
			"diff --git a/Dir b/Name b/Dir b/Name"
		))
		#expect(pairs.count == 3)
		#expect(pairs.map(\.old) == ["Dir", "Dir b/Name", "Dir b/Name b/Dir"])
		#expect(pairs.map(\.new) == ["Name b/Dir b/Name", "Dir b/Name", "Name"])
		#expect(Array(GitPatchSyntax.unquotedHeaderCandidates("diff --cc a/file")).isEmpty)
	}
}
