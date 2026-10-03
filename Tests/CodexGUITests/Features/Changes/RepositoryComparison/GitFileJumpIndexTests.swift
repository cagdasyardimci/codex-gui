import Testing

@testable import CodexGUI

@Suite
struct GitFileJumpIndexTests
{
	@Test func filenameDirectoryAndFullPathQueriesKeepDuplicateBasenamesDistinct()
	{
		func file(_ path: String) -> GitComparisonFile
		{
			GitComparisonFile(
				oldPath: path,
				newPath: path,
				kind: .modified,
				additions: 1,
				deletions: 1,
				isBinary: false,
				patch: "",
				hunks: []
			)
		}
		let index = GitFileJumpIndex(files: [
			file("Sources/First/Shared.swift"),
			file("Tests/Second/Shared.swift"),
			file("Sources/First/Unique.swift"),
		])
		#expect(index.matches("shared").map(\.id) == [
			"Sources/First/Shared.swift",
			"Tests/Second/Shared.swift"
		])
		#expect(index.matches("first").map(\.id) == [
			"Sources/First/Shared.swift",
			"Sources/First/Unique.swift"
		])
		#expect(index.matches("first/shared").map(\.id) == ["Sources/First/Shared.swift"])
		#expect(index.matches(" SECOND/SHARED ").map(\.id) == ["Tests/Second/Shared.swift"])
		#expect(index.entries[0].filename == "Shared.swift")
		#expect(index.entries[0].directory == "Sources/First")
	}
}
