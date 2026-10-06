import Foundation
import Testing

@testable import CodexGUI

struct FileSystemProjectFileIndexServiceTests
{
	@Test func externalTargetsAppearAndDisappearWithoutMakingTheIndexReusable() async throws
	{
		let directory = try makeTemporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let project = directory.appendingPathComponent(
			"checkout",
			isDirectory: true
		)
		let external = directory.appendingPathComponent("external.swift")
		try FileManager.default.createDirectory(
			at: project,
			withIntermediateDirectories: true
		)
		try FileManager.default.createSymbolicLink(
			at: project.appendingPathComponent("linked.swift"),
			withDestinationURL: external
		)
		let service = FileSystemProjectFileIndexService()
		let dangling = try #require(await service.load(projectPath: project.path))
		#expect(dangling.files.isEmpty)
		#expect(!dangling.isReusableWithProjectObservation)

		try "content".write(
			to: external,
			atomically: true,
			encoding: .utf8
		)
		let present = try #require(await service.load(projectPath: project.path))
		#expect(present.files == ["linked.swift"])
		#expect(!present.isReusableWithProjectObservation)
		try FileManager.default.removeItem(at: external)
		let removed = try #require(await service.load(projectPath: project.path))
		#expect(removed.files.isEmpty)
		#expect(!removed.isReusableWithProjectObservation)
	}

	@Test func ignoredLinksAndDirectoriesKeepTheirExistingEnumerationRules() async throws
	{
		let directory = try makeTemporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let project = directory.appendingPathComponent(
			"checkout",
			isDirectory: true
		)
		let external = directory.appendingPathComponent(
			"external",
			isDirectory: true
		)
		for folder in [project, external]
		{
			try FileManager.default.createDirectory(
				at: folder,
				withIntermediateDirectories: true
			)
		}
		try "visible".write(
			to: project.appendingPathComponent("visible.swift"),
			atomically: true,
			encoding: .utf8
		)
		try "dependency".write(
			to: external.appendingPathComponent("dependency.swift"),
			atomically: true,
			encoding: .utf8
		)
		try FileManager.default.createSymbolicLink(
			at: project.appendingPathComponent("node_modules"),
			withDestinationURL: external
		)
		try FileManager.default.createSymbolicLink(
			at: project.appendingPathComponent(".hidden"),
			withDestinationURL: directory.appendingPathComponent("absent.swift")
		)
		let index = try #require(
			await FileSystemProjectFileIndexService().load(projectPath: project.path)
		)
		#expect(index.files == ["visible.swift"])
		#expect(index.isReusableWithProjectObservation)
	}

	@Test func fileSearchIncludesSourceAndSkipsBuildDirectories() async throws
	{
		let project = try makeTemporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let source = project.appendingPathComponent("Sources/Example.swift")
		let ignored = project.appendingPathComponent("node_modules/Example.swift")
		try FileManager.default.createDirectory(
			at: source.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		try FileManager.default.createDirectory(
			at: ignored.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		try "source".write(
			to: source,
			atomically: true,
			encoding: .utf8
		)
		try "ignored".write(
			to: ignored,
			atomically: true,
			encoding: .utf8
		)
		let index = try #require(await FileSystemProjectFileIndexService().load(
			projectPath: project.path
		))
		#expect(index.search("Exam") == ["Sources/Example.swift"])
	}

	private func makeTemporaryDirectory() throws -> URL
	{
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
			"ProjectFileIndexService-\(UUID().uuidString)",
			isDirectory: true
		)
		try FileManager.default.createDirectory(
			at: directory,
			withIntermediateDirectories: true
		)
		return directory
	}
}
