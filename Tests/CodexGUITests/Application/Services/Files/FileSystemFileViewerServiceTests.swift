import Darwin
import Foundation
import Testing

@testable import CodexGUI

@Suite(.timeLimit(.minutes(1)))
struct FileSystemFileViewerServiceTests
{

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

	@Test
	func documentReadsAndSaveReplacementRejectNamedPipesWithoutWaiting() async throws
	{
		let fixture = try FileReadSafetyFixture()
		defer
		{
			try? FileManager.default.removeItem(at: fixture.root)
		}
		let location = FileLocation(
			root: fixture.root.path,
			relativePath: "document.txt"
		)
		let service = FileSystemFileViewerService()
		try Data("original".utf8).write(to: location.fileURL)
		let loaded = try await service.read(at: location)
		try FileManager.default.removeItem(at: location.fileURL)
		let pipe = try fixture.makePipe(named: "document.txt")
		for saving in [false, true]
		{
			let rescue = FileReadSafetyFixture.rescueBlockedOpen(at: pipe)
			defer
			{
				rescue.cancel()
			}
			await #expect(throws: FileViewerFailure.invalidPath)
			{
				if saving
				{
					_ = try await service.save(
						at: location,
						text: "local edit",
						expectedRevision: loaded.revision
					)
				}
				else
				{
					_ = try await service.read(at: location)
				}
			}
			rescue.cancel()
			#expect(await rescue.value == false)
		}
		let sparse = try fixture.makeSparseFile(
			named: "large.txt",
			byteCount: 8 * 1024 * 1024 * 1024
		)
		await #expect(throws: FileViewerFailure.tooLarge)
		{
			_ = try await service.read(at: FileLocation(
				root: fixture.root.path,
				relativePath: sparse.lastPathComponent
			))
		}
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
