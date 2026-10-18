import Foundation
import Testing

@testable import CodexGUI

struct CodeSelectionSourceLoaderTests
{
	@Test func boundedSourcePreservesExactUnicodeAndLineSeparators() async throws
	{
		let directory = try fixture()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let file = directory.appendingPathComponent("code.swift")
		let text = "cafe\u{301} 😀\r\nsecond\u{2028}"
		try Data(text.utf8).write(to: file)
		let source = try await CodeSelectionSourceLoader.load(
			projectPath: directory.path,
			file: file
		)
		#expect(source.relativePath == "code.swift")
		#expect(source.contents.utf8.elementsEqual(text.utf8))
	}

	@Test(arguments: [500_001, 1])
	func oversizedAndInvalidUTF8SourcesRetainTheirRejectionPolicy(byteCount: Int) async throws
	{
		let directory = try fixture()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let file = directory.appendingPathComponent("unsupported.swift")
		try Data(
			repeating: 0xFF,
			count: byteCount
		).write(to: file)
		await #expect(throws: CodeSelectionSourceLoader.Failure.self)
		{
			try await CodeSelectionSourceLoader.load(
				projectPath: directory.path,
				file: file
			)
		}
	}

	@Test func containedSymlinkResolvesAndAnExternalTargetRemainsRejected() async throws
	{
		let directory = try fixture()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let project = directory.appendingPathComponent("project")
		try FileManager.default.createDirectory(
			at: project,
			withIntermediateDirectories: true
		)
		let target = project.appendingPathComponent("source.swift")
		try Data("inside".utf8).write(to: target)
		let link = project.appendingPathComponent("alias.swift")
		try FileManager.default.createSymbolicLink(
			at: link,
			withDestinationURL: target
		)
		let source = try await CodeSelectionSourceLoader.load(
			projectPath: project.path,
			file: link
		)
		#expect(source.relativePath == "source.swift")
		let outside = directory.appendingPathComponent("outside.swift")
		try Data("outside".utf8).write(to: outside)
		let external = project.appendingPathComponent("external.swift")
		try FileManager.default.createSymbolicLink(
			at: external,
			withDestinationURL: outside
		)
		await #expect(throws: CodeSelectionSourceLoader.Failure.self)
		{
			try await CodeSelectionSourceLoader.load(
				projectPath: project.path,
				file: external
			)
		}
	}

	private func fixture() throws -> URL
	{
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(
			at: directory,
			withIntermediateDirectories: true
		)
		return directory
	}
}
