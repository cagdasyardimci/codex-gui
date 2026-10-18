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
