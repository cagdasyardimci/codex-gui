import Foundation
import Testing

@testable import CodexGUI

@Suite(.timeLimit(.minutes(1)))
struct ComposerCodeFileReaderTests
{
	@Test @MainActor
	func chosenTextKeepsExactBytesAndProjectRelativePath() async throws
	{
		let fixture = try await BackgroundTestWork.perform
		{
			let fixture = try FileReadSafetyFixture()
			let directory = fixture.root.appendingPathComponent("Sources")
			try FileManager.default.createDirectory(
				at: directory,
				withIntermediateDirectories: true
			)
			try Data("α\r\n😀\n".utf8).write(to: directory.appendingPathComponent("Example.swift"))
			return fixture
		}
		defer
		{
			try? FileManager.default.removeItem(at: fixture.root)
		}
		let selected = try await ComposerCodeFileReader.read(
			file: fixture.root.appendingPathComponent("Sources/Example.swift"),
			project: fixture.root
		)
		#expect(selected.relativePath == "Sources/Example.swift")
		#expect(selected.contents == "α\r\n😀\n")
	}

	@Test
	func namedPipeAndOversizedSparseFileAreRejectedBeforeReading() async throws
	{
		let fixture = try FileReadSafetyFixture()
		defer
		{
			try? FileManager.default.removeItem(at: fixture.root)
		}
		let pipe = try fixture.makePipe(named: "blocking.swift")
		let rescue = FileReadSafetyFixture.rescueBlockedOpen(at: pipe)
		defer
		{
			rescue.cancel()
		}
		await #expect(throws: FileViewerFailure.invalidPath)
		{
			_ = try await ComposerCodeFileReader.read(
				file: pipe,
				project: fixture.root
			)
		}
		rescue.cancel()
		#expect(await rescue.value == false)
		let sparse = try fixture.makeSparseFile(
			named: "huge.swift",
			byteCount: 8 * 1024 * 1024 * 1024
		)
		await #expect(throws: FileViewerFailure.tooLarge)
		{
			_ = try await ComposerCodeFileReader.read(
				file: sparse,
				project: fixture.root
			)
		}
	}

	@Test
	func siblingAndSymlinkEscapeAreRejected() async throws
	{
		let fixture = try FileReadSafetyFixture()
		let outside = try FileReadSafetyFixture()
		defer
		{
			try? FileManager.default.removeItem(at: fixture.root)
			try? FileManager.default.removeItem(at: outside.root)
		}
		let source = outside.root.appendingPathComponent("outside.swift")
		try Data("outside".utf8).write(to: source)
		let link = fixture.root.appendingPathComponent("link.swift")
		try FileManager.default.createSymbolicLink(
			at: link,
			withDestinationURL: source
		)
		for file in [source, link]
		{
			await #expect(throws: FileViewerFailure.invalidPath)
			{
				_ = try await ComposerCodeFileReader.read(
					file: file,
					project: fixture.root
				)
			}
		}
	}

	@Test
	func invalidUTF8AndBinaryAreRejected() async throws
	{
		let fixture = try FileReadSafetyFixture()
		defer
		{
			try? FileManager.default.removeItem(at: fixture.root)
		}
		let file = fixture.root.appendingPathComponent("invalid.swift")
		for bytes in [Data([0xFF]), Data([0, 65])]
		{
			try bytes.write(to: file)
			await #expect(throws: FileViewerFailure.unsupportedEncoding)
			{
				_ = try await ComposerCodeFileReader.read(
					file: file,
					project: fixture.root
				)
			}
		}
	}
}
