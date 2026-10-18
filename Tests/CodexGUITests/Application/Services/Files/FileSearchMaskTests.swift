import Foundation
import Testing

@testable import CodexGUI

struct FileSearchMaskTests
{
	@Test(arguments: [
		(nil as String?, "Sources/main.swift", true),
		("", "Sources/main.swift", true),
		(",", "Sources/main.swift", false),
		("*.swift", "Sources/MAIN.SWIFT", true),
		("*.swift", "Sources/main.swift.txt", false),
		("*.md, *.swift", "Sources/main.swift", true),
		("*.md, *.swift", "Sources/main.txt", false),
		("Sources/*.swift", "Sources/main.swift", true),
		("Sources/*.swift", "Other/Sources/main.swift", false),
		("**/Sources/*.swift", "Sources/main.swift", true),
		("**/Sources/*.swift", "Other/Sources/main.swift", true),
		("**/Sources/*.swift", "Other/Sources/Nested/main.swift", true),
		("**/Sources/*.swift", "Other/main.swift", false),
		("**/*.swift", "main.swift", true),
		("**/*.swift", "Other/Nested/main.swift", true),
		("**/*.{md, swift}", "Other/Nested/main.SWIFT", true),
		("**/*.{md, swift}", "Other/Nested/main.txt", false),
		("**/{.hidden,main}.swift", "Other/.hidden.swift", true),
		("*.{swift,}", "Other/main.swift", true),
		("*.{}", "Other/main.swift", false),
		("**/src/*.swift", "src/émoji😀.swift", true),
		("**/src/*.swift", "émoji😀/src/main.swift", true),
		("main[12].swift", "Other/main2.swift", true),
		("main[12].swift", "Other/main3.swift", false),
	])
	func masksPreserveBasenamePathAndRecursiveMatching(
		mask: String?,
		path: String,
		expected: Bool
	)
	{
		#expect(FileSearchMask(mask).matches(path) == expected)
	}

	@Test
	func braceAlternativesRetainTheExpansionLimit()
	{
		let alternatives = (0 ..< 33).map(String.init).joined(separator: ",")
		let mask = FileSearchMask("**/file.{\(alternatives)}")
		#expect(mask.matches("nested/file.0"))
		#expect(mask.matches("nested/file.31"))
		#expect(!mask.matches("nested/file.32"))
	}
}
