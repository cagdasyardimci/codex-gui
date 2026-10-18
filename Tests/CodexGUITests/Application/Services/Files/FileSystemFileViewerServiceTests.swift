import Darwin
import Foundation
import Testing

@testable import CodexGUI

@Suite(.timeLimit(.minutes(1)))
struct FileSystemFileViewerServiceTests
{
	@Test
	func roundTripPreservesExactUTF8AndMixedLineEndings() async throws
	{
		let root = try fixture()
		defer
		{
			try? FileManager.default.removeItem(atPath: root)
		}
		let location = FileLocation(
			root: root,
			relativePath: "notes/émoji.txt"
		)
		try FileManager.default.createDirectory(
			at: URL(fileURLWithPath: root).appendingPathComponent("notes"),
			withIntermediateDirectories: true
		)
		let original = "α\r\nβ\n😀\rfin\n"
		try Data(original.utf8).write(to: location.fileURL)
		let service = FileSystemFileViewerService()
		let loaded = try await service.read(at: location)
		#expect(loaded.content == .text(original))
		let unchanged = try await service.save(
			at: location,
			text: original,
			expectedRevision: loaded.revision
		)
		#expect(unchanged == loaded.revision)
		#expect(try Data(contentsOf: location.fileURL) == Data(original.utf8))
		let changed = "α\r\nβ\n😀\rfin!\n"
		let newRevision = try await service.save(
			at: location,
			text: changed,
			expectedRevision: unchanged
		)
		#expect(newRevision != unchanged)
		#expect(try Data(contentsOf: location.fileURL) == Data(changed.utf8))
	}

	@Test
	func hiddenEntriesAndEmptyDirectoriesAreBrowsable() async throws
	{
		let root = try fixture()
		defer
		{
			try? FileManager.default.removeItem(atPath: root)
		}
		let empty = URL(fileURLWithPath: root).appendingPathComponent("empty")
		try FileManager.default.createDirectory(
			at: empty,
			withIntermediateDirectories: true
		)
		try Data().write(to: URL(fileURLWithPath: root).appendingPathComponent(".hidden"))
		let service = FileSystemFileViewerService()
		let entries = try await service.listDirectory(at: FileLocation(
			root: root,
			relativePath: ""
		))
		#expect(entries.map(\.name) == ["empty", ".hidden"])
		#expect(try await service.listDirectory(at: FileLocation(
			root: root,
			relativePath: "empty"
		))
		.isEmpty)
	}

	@Test
	func traversalAndSymbolicLinksCannotEscapeRoot() async throws
	{
		let root = try fixture()
		let outside = try fixture()
		defer
		{
			try? FileManager.default.removeItem(atPath: root)
			try? FileManager.default.removeItem(atPath: outside)
		}
		let external = URL(fileURLWithPath: outside).appendingPathComponent("secret.txt")
		try Data("secret".utf8).write(to: external)
		try FileManager.default.createSymbolicLink(
			at: URL(fileURLWithPath: root).appendingPathComponent("link"),
			withDestinationURL: URL(fileURLWithPath: outside)
		)
		let service = FileSystemFileViewerService()
		let entries = try await service.listDirectory(at: FileLocation(
			root: root,
			relativePath: ""
		))
		#expect(entries.map(\.name) == ["link"])
		#expect(entries.first?.isSymbolicLink == true)
		await #expect(throws: FileViewerFailure.self)
		{
			_ = try await service.read(at: FileLocation(
				root: root,
				relativePath: "../secret.txt"
			))
		}
		await #expect(throws: FileViewerFailure.self)
		{
			_ = try await service.read(at: FileLocation(
				root: root,
				relativePath: "link/secret.txt"
			))
		}
		#expect(try Data(contentsOf: external) == Data("secret".utf8))
	}

	@Test
	func malformedBinaryOversizedAndConflictKeepDiskBytes() async throws
	{
		let root = try fixture()
		defer
		{
			try? FileManager.default.removeItem(atPath: root)
		}
		let file = FileLocation(
			root: root,
			relativePath: "file.txt"
		)
		let service = FileSystemFileViewerService()
		try Data([0xFF]).write(to: file.fileURL)
		await #expect(throws: FileViewerFailure.unsupportedEncoding)
		{
			_ = try await service.read(at: file)
		}
		try Data([0, 1]).write(to: file.fileURL)
		await #expect(throws: FileViewerFailure.binary)
		{
			_ = try await service.read(at: file)
		}
		try Data(
			repeating: 65,
			count: FileSystemFileViewerService.maximumReadBytes + 1
		)
		.write(to: file.fileURL)
		await #expect(throws: FileViewerFailure.tooLarge)
		{
			_ = try await service.read(at: file)
		}
		try Data("old".utf8).write(to: file.fileURL)
		let old = try await service.read(at: file)
		let replacement = URL(fileURLWithPath: root).appendingPathComponent("replacement")
		try Data("external".utf8).write(to: replacement)
		try FileManager.default.replaceItemAt(
			file.fileURL,
			withItemAt: replacement
		)
		await #expect(throws: FileViewerFailure.conflict)
		{
			_ = try await service.save(
				at: file,
				text: "local",
				expectedRevision: old.revision
			)
		}
		#expect(try Data(contentsOf: file.fileURL) == Data("external".utf8))
	}

	@Test
	func searchFindsHiddenPathsAndLiteralLinesWithMasks() async throws
	{
		let root = try fixture()
		defer
		{
			try? FileManager.default.removeItem(atPath: root)
		}
		try Data("first\r\nneedle here\rneedle again\n".utf8)
			.write(to: URL(fileURLWithPath: root).appendingPathComponent(".hidden.md"))
		try Data("needle excluded".utf8)
			.write(to: URL(fileURLWithPath: root).appendingPathComponent("other.txt"))
		let service = FileSystemFileViewerService()
		let names = try await service.filenameSearch(
			root: root,
			query: "hidden",
			limit: 1
		)
		#expect(names.results.map(\.relativePath) == [".hidden.md"])
		let content = try await service.contentSearch(
			root: root,
			query: "needle",
			mask: "*.md",
			limit: 1
		)
		#expect(content.results.map(\.lineNumber) == [2])
		#expect(content.results.map(\.lineText) == ["needle here"])
		#expect(content.isTruncated)
		let braceMask = try await service.contentSearch(
			root: root,
			query: "needle",
			mask: "**/{.hidden,missing}.md",
			limit: 3
		)
		#expect(braceMask.results.map(\.lineNumber) == [2, 3])
	}

	@Test
	func textBeyondEditBudgetLoadsReadOnlyAndPermissionFailureRetainsBytes() async throws
	{
		let root = try fixture()
		defer
		{
			try? FileManager.default.removeItem(atPath: root)
		}
		let location = FileLocation(
			root: root,
			relativePath: "large.txt"
		)
		let bytes = Data(
			repeating: 65,
			count: FileSystemFileViewerService.maximumTextBytes + 1
		)
		try bytes.write(to: location.fileURL)
		let service = FileSystemFileViewerService()
		let loaded = try await service.read(at: location)
		#expect(loaded.isReadOnly)
		if case .text(let text) = loaded.content
		{
			#expect(text.utf8.count == bytes.count)
		}
		else
		{
			Issue.record("Large valid UTF-8 text should remain readable")
		}
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o444],
			ofItemAtPath: location.fileURL.path
		)
		await #expect(throws: FileViewerFailure.readOnly)
		{
			_ = try await service.save(
				at: location,
				text: "replace",
				expectedRevision: loaded.revision
			)
		}
		#expect(try Data(contentsOf: location.fileURL) == bytes)
	}

	@Test
	func malformedMediaAndEmptyImageCannotBeEdited() async throws
	{
		let root = try fixture()
		defer
		{
			try? FileManager.default.removeItem(atPath: root)
		}
		let image = FileLocation(
			root: root,
			relativePath: "image.png"
		)
		let pdf = FileLocation(
			root: root,
			relativePath: "paper.pdf"
		)
		let service = FileSystemFileViewerService()
		try Data().write(to: image.fileURL)
		let empty = try await service.read(at: image)
		#expect(empty.content == .empty)
		#expect(empty.isReadOnly)
		try Data("bad image".utf8).write(to: image.fileURL)
		let malformedImage = try await service.read(at: image)
		#expect(malformedImage.content == .unsupported)
		#expect(malformedImage.isReadOnly)
		try Data("bad pdf".utf8).write(to: pdf.fileURL)
		let malformedPDF = try await service.read(at: pdf)
		#expect(malformedPDF.content == .unsupported)
		#expect(malformedPDF.isReadOnly)
	}

	@Test
	func recursiveSearchSkipsGeneratedTreesButFindsHiddenConfigAndSource() async throws
	{
		let root = try fixture()
		defer
		{
			try? FileManager.default.removeItem(atPath: root)
		}
		for directory in [".build", ".config", "Sources"]
		{
			try FileManager.default.createDirectory(
				at: URL(fileURLWithPath: root).appendingPathComponent(directory),
				withIntermediateDirectories: true
			)
		}
		for (path, text) in [
			(".build/generated.swift", "needle generated"),
			(".config/settings.md", "needle config"),
			("Sources/main.swift", "needle source"),
		]
		{
			try Data(text.utf8).write(to: URL(fileURLWithPath: root).appendingPathComponent(path))
		}
		let service = FileSystemFileViewerService()
		let names = try await service.filenameSearch(
			root: root,
			query: "",
			limit: 20
		)
		#expect(Set(names.results.map(\.relativePath)) == [
			".config/settings.md",
			"Sources/main.swift",
		])
		#expect(names.excludedDirectoryCount == 1)
		let content = try await service.contentSearch(
			root: root,
			query: "needle",
			mask: "**/*.{md,swift}",
			limit: 20
		)
		#expect(Set(content.results.map(\.lineText)) == ["needle config", "needle source"])
		#expect(content.excludedDirectoryCount == 1)
	}

	@Test
	func warmSearchSeesNestedAddEditRemovalAndRootSwitch() async throws
	{
		let firstRoot = try fixture()
		let secondRoot = try fixture()
		defer
		{
			try? FileManager.default.removeItem(atPath: firstRoot)
			try? FileManager.default.removeItem(atPath: secondRoot)
		}
		let nested = URL(fileURLWithPath: firstRoot).appendingPathComponent("nested")
		try FileManager.default.createDirectory(
			at: nested,
			withIntermediateDirectories: true
		)
		let first = nested.appendingPathComponent("first.md")
		let added = nested.appendingPathComponent("added.md")
		try Data("old".utf8).write(to: first)
		try Data("other".utf8).write(
			to: URL(fileURLWithPath: secondRoot).appendingPathComponent("other.md")
		)
		let service = FileSystemFileViewerService()
		#expect(try await service.filenameSearch(
			root: firstRoot,
			query: "",
			limit: 10
		)
		.results.map(\.relativePath) == ["nested/first.md"])
		try Data("new".utf8).write(to: first)
		try Data("new".utf8).write(to: added)
		#expect(try await service.contentSearch(
			root: firstRoot,
			query: "new",
			mask: nil,
			limit: 10
		)
		.results.map(\.location.relativePath) == ["nested/added.md", "nested/first.md"])
		try FileManager.default.removeItem(at: first)
		#expect(try await service.filenameSearch(
			root: firstRoot,
			query: "",
			limit: 10
		)
		.results.map(\.relativePath) == ["nested/added.md"])
		#expect(try await service.filenameSearch(
			root: secondRoot,
			query: "",
			limit: 10
		)
		.results.map(\.relativePath) == ["other.md"])
	}

	@Test
	func searchPreservesLiteralUnicodeLinesRankingAndLimits() async throws
	{
		let root = try fixture()
		defer
		{
			try? FileManager.default.removeItem(atPath: root)
		}
		for (name, text) in [
			("prefix.swift", "α😀\r\nN.EED\u{2028}needle\rN.EED"),
			("sub/needle.swift", "needle"),
			("needle.md", "needle"),
		]
		{
			let url = URL(fileURLWithPath: root).appendingPathComponent(name)
			try FileManager.default.createDirectory(
				at: url.deletingLastPathComponent(),
				withIntermediateDirectories: true
			)
			try Data(text.utf8).write(to: url)
		}
		let service = FileSystemFileViewerService()
		let names = try await service.filenameSearch(
			root: root,
			query: "needle",
			limit: 1
		)
		#expect(names.results.map(\.relativePath) == ["needle.md"])
		#expect(names.isTruncated)
		let content = try await service.contentSearch(
			root: root,
			query: "N.EED",
			mask: "**/*.{SWIFT,txt}",
			limit: 1
		)
		#expect(content.results.map(\.lineNumber) == [2])
		#expect(content.results.map(\.lineText) == ["N.EED"])
		#expect(content.isTruncated)
		let literal = try await service.contentSearch(
			root: root,
			query: ".",
			mask: "*.swift",
			limit: 10
		)
		#expect(literal.results.map(\.lineNumber) == [2, 4])
		let acrossLines = try await service.contentSearch(
			root: root,
			query: "N.EED\u{2028}needle",
			mask: "*.swift",
			limit: 10
		)
		#expect(acrossLines.results.isEmpty)
		let absent = try await service.contentSearch(
			root: root,
			query: "missing phrase",
			mask: "*.swift",
			limit: 10
		)
		#expect(absent.results.isEmpty)
	}

	@Test(arguments: ["strasse", "😀", "é", "i"])
	func sparseContentSearchPreservesUnicodeAndEveryLogicalLineEnding(query: String) async throws
	{
		let root = try fixture()
		defer
		{
			try? FileManager.default.removeItem(atPath: root)
		}
		let lines = ["😀 STRASSE", "Straße", "E\u{301} I", "Straße 😀", "É İ", "strasse ß"]
		let separators = ["\r\n", "\r", "\n", "\u{2028}", "\u{2029}", "\n"]
		let prefix = String(
			repeating: "x\n",
			count: 1_000
		)
		let text = prefix + zip(
			lines,
			separators
		).map
		{
			$0 + $1
		}.joined()
		try Data(text.utf8).write(
			to: URL(fileURLWithPath: root).appendingPathComponent("unicode.txt")
		)
		let service = FileSystemFileViewerService()
		let page = try await service.contentSearch(
			root: root,
			query: query,
			mask: "*.txt",
			limit: 20
		)
		let expectedIndices = lines.indices.filter
		{
			lines[$0].range(
				of: query,
				options: [.caseInsensitive, .literal]
			) != nil
		}
		#expect(page.results.map(\.lineNumber) == expectedIndices.map
		{
			$0 + 1_001
		})
		#expect(page.results.map(\.lineText) == expectedIndices.map
		{
			lines[$0]
		})
		#expect(!page.isTruncated)
	}

	@Test
	func canceledSearchStopsBeforePublishingResults() async throws
	{
		let root = try fixture()
		defer
		{
			try? FileManager.default.removeItem(atPath: root)
		}
		try Data("needle".utf8).write(
			to: URL(fileURLWithPath: root).appendingPathComponent("file.txt")
		)
		let service = FileSystemFileViewerService()
		let operation = Task
		{
			withUnsafeCurrentTask
			{
				$0?.cancel()
			}
			return try await service.filenameSearch(
				root: root,
				query: "file",
				limit: 10
			)
		}
		await #expect(throws: CancellationError.self)
		{
			_ = try await operation.value
		}
	}

	@Test
	func contentSearchSkipsNamedPipesAndMediaButIncludesSVGText() async throws
	{
		let root = try fixture()
		defer
		{
			try? FileManager.default.removeItem(atPath: root)
		}
		let rootURL = URL(fileURLWithPath: root)
		let pipe = rootURL.appendingPathComponent("blocking.txt")
		let pipeResult = pipe.path.withCString
		{
			Darwin.mkfifo(
				$0,
				0o600
			)
		}
		guard pipeResult == 0
		else
		{
			throw NSError(
				domain: NSPOSIXErrorDomain,
				code: Int(errno)
			)
		}
		try Data("needle".utf8).write(to: rootURL.appendingPathComponent("malformed.png"))
		try Data([0xFF, 0xFE]).write(to: rootURL.appendingPathComponent("invalid.svg"))
		try Data("<svg>needle</svg>".utf8).write(to: rootURL.appendingPathComponent("vector.svg"))
		let service = FileSystemFileViewerService()
		let page = try await service.contentSearch(
			root: root,
			query: "needle",
			mask: nil,
			limit: 10
		)
		#expect(page.results.map(\.location.relativePath) == ["vector.svg"])
		#expect(page.results.map(\.lineText) == ["<svg>needle</svg>"])
	}

	/// Set FILE_SEARCH_BENCHMARK=1 for comparable cold and warm service timings.
	@Test
	func searchTimingDiagnostic() async throws
	{
		guard ProcessInfo.processInfo.environment["FILE_SEARCH_BENCHMARK"] == "1"
		else
		{
			return
		}
		let root = try fixture()
		defer
		{
			try? FileManager.default.removeItem(atPath: root)
		}
		for directoryIndex in 0 ..< 50
		{
			let directory = URL(fileURLWithPath: root)
				.appendingPathComponent(String(
					format: "dir-%02d",
					directoryIndex
				))
			try FileManager.default.createDirectory(
				at: directory,
				withIntermediateDirectories: true
			)
			for fileIndex in 0 ..< 100
			{
				try Data("sample text\n".utf8).write(
					to: directory.appendingPathComponent(
						String(
							format: "file-%03d.swift",
							fileIndex
						)
					)
				)
			}
		}
		let service = FileSystemFileViewerService()
		let start = DispatchTime.now().uptimeNanoseconds
		let cold = try await service.filenameSearch(
			root: root,
			query: "file-050",
			limit: 20
		)
		let coldEnd = DispatchTime.now().uptimeNanoseconds
		let warm = try await service.filenameSearch(
			root: root,
			query: "file-051",
			limit: 20
		)
		let warmEnd = DispatchTime.now().uptimeNanoseconds
		let content = try await service.contentSearch(
			root: root,
			query: "sample",
			mask: "*.swift",
			limit: 20
		)
		let contentEnd = DispatchTime.now().uptimeNanoseconds
		#expect(cold.results.count == 20)
		#expect(warm.results.count == 20)
		#expect(content.results.count == 20)
		print("FILE_SEARCH_BENCHMARK files=5000 cold_filename_ms="
			+ "\(Double(coldEnd - start) / 1_000_000) warm_filename_ms="
			+ "\(Double(warmEnd - coldEnd) / 1_000_000) content_ms="
			+ "\(Double(contentEnd - warmEnd) / 1_000_000)")
	}

	private func fixture() throws -> String
	{
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent("file-viewer-\(UUID().uuidString)")
		try FileManager.default.createDirectory(
			at: root,
			withIntermediateDirectories: true
		)
		return root.path
	}
}
