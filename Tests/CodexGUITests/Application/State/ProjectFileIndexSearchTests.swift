import Foundation
import Testing

@testable import CodexGUI

struct ProjectFileIndexSearchTests
{
	@Test func rankingCategoriesAndSourceOrderTiesRemainStable()
	{
		let files = [
			"deep/file/Other.swift",
			"file/Other.swift",
			"b/file",
			"a/file",
			"files.swift",
			"Longer/midfile.swift",
			"aa/file",
			"0/File",
			"FILE",
			"file/same",
		]
		let index = ProjectFileIndex(files: files)
		#expect(index.search(
			"file",
			limit: 5
		) == ["FILE", "b/file", "a/file", "0/File", "aa/file"])
		#expect(index.search(
			"file",
			limit: 20
		) == previousSearch(
			files,
			query: "file",
			limit: 20
		))
		#expect(index.search(
			"  ",
			limit: 3
		) == Array(files.prefix(3)))
		#expect(index.search(
			"file",
			limit: 0
		).isEmpty)
		#expect(ProjectFileIndex(files: []).search("file").isEmpty)
	}

	@Test func unicodeURLBasenamesAndVariedLimitsMatchThePreviousAlgorithm()
	{
		let files = [
			"Sources/café.swift",
			"Sources/cafe\u{0301}.swift",
			"Sources/CAFÉ.swift",
			"Sources/İstanbul.swift",
			"Sources/i\u{0307}stanbul.swift",
			"Sources/Straße.swift",
			"Sources/👨‍👩‍👧‍👦file.swift",
			"🧭/File.swift",
			"a/file.swift",
			"B/FILE.swift",
			"File/Other.swift",
			"one/file/Other.swift",
			"Sources/notes%20file.swift",
			"Sources/notes file.swift",
			"Sources/line\u{2028}file.swift",
			"Sources/tab\tfile.swift",
			"Folder\\File.swift",
			"/absolute/FILE/",
			"Sources/./File.swift",
			"Sources/nested/../File.swift",
			"Sources/a+b#file.swift",
			"README",
			"",
		]
		let index = ProjectFileIndex(files: files)
		let queries = [
			"",
			" \t\n",
			"file",
			" SWIFT\n",
			"CAFÉ",
			"cafe\u{0301}",
			"İ",
			"i\u{0307}",
			"straße",
			"Sources/",
			"missing",
			"%20",
			".swift",
			"🧭",
			"👨‍👩‍👧‍👦",
			"\u{2028}",
		]
		for query in queries
		{
			let expected = previousSearch(
				files,
				query: query,
				limit: files.count
			)
			for limit in [0, 1, 2, 3, 7, 12, files.count, files.count + 20, Int.max]
			{
				let actual = index.search(
					query,
					limit: limit
				)
				#expect(actual.map
				{
					Data($0.utf8)
				} == expected.prefix(limit)
				.map
				{
					Data($0.utf8)
				})
			}
		}
		#expect(index.files.map
		{
			Data($0.utf8)
		} == files.map
		{
			Data($0.utf8)
		})
	}

	@Test func broadMatchesInFiftyThousandFilesMatchTheFullRankingOracle()
	{
		let files = (0 ..< 50_000).map
		{
			index in
			let number = (index * 8191 + 373) % 50_000
			let suffix = String(
				format: "%05d",
				number
			)
			switch number % 5
			{
			case 0: return "Files/Group\(number % 13)/file-\(suffix).swift"
			case 1: return "Files/Group\(number % 13)/a-file-\(suffix).swift"
			case 2: return "Files/Group\(number % 13)/other-\(suffix).swift"
			case 3: return "Files/Group\(number % 13)/file/other-\(suffix).swift"
			default: return "Files/Group\(number % 13)/\(suffix)/FILE"
			}
		}
		let index = ProjectFileIndex(files: files)
		for query in ["file", ".swift", "Files/"]
		{
			let expected = previousSearch(
				files,
				query: query,
				limit: files.count
			)
			for limit in [1, 12, 97, files.count + 1]
			{
				#expect(index.search(
					query,
					limit: limit
				) == Array(expected.prefix(limit)))
			}
		}
	}

	@Test func valueCopiesKeepTheirOriginalPreparedPaths()
	{
		var files = ["Sources/cafe\u{0301}.swift", "Sources/Second.swift"]
		let index = ProjectFileIndex(files: files)
		let copy = index
		files[0] = "Sources/Replaced.swift"
		#expect(copy.search("café").first?.utf8.elementsEqual("Sources/cafe\u{0301}.swift".utf8)
			== true)
		#expect(index.search("replaced").isEmpty)
		#expect(ProjectFileIndex(files: files).search("replaced") == ["Sources/Replaced.swift"])
	}

	/// The former full-match/full-sort implementation is the behavior oracle.
	private func previousSearch(
		_ files: [String],
		query: String,
		limit: Int
	) -> [String]
	{
		let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		guard !normalized.isEmpty
		else
		{
			return Array(files.prefix(limit))
		}
		let matches = files.compactMap
		{
			path -> (path: String, score: Int)? in
			let lowercased = path.lowercased()
			let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
			let score: Int
			if name == normalized
			{
				score = 0
			}
			else if name.hasPrefix(normalized)
			{
				score = 1
			}
			else if name.contains(normalized)
			{
				score = 2
			}
			else if lowercased.hasPrefix(normalized)
			{
				score = 3
			}
			else if lowercased.contains(normalized)
			{
				score = 4
			}
			else
			{
				return nil
			}
			return (path, score)
		}
		return matches.sorted
		{
			$0.score == $1.score ? $0.path.count < $1.path.count : $0.score < $1.score
		}.prefix(limit).map(\.path)
	}
}
