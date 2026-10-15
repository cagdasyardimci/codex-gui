import AppKit
import Foundation
import Testing

@testable import CodexGUI

@Suite @MainActor
struct EditorOpeningServiceTests
{
	@Test func rejectsAbsolutePathsOutsideProjectAndMissingFiles() async throws
	{
		let root = try await temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: root)
		}
		let outsideDirectory = try await temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: outsideDirectory)
		}
		let defaultsFixture = try IsolatedUserDefaultsFixture(prefix: "EditorOpeningServiceTests")
		defer
		{
			defaultsFixture.cleanup()
		}
		let editor = EditorOpeningService(defaults: defaultsFixture.defaults)
		let missingProject = root.appendingPathComponent("missing-project")
		await #expect
		{
			try await editor.open(
				path: "file.swift",
				project: missingProject,
				line: 1
			)
		} throws:
		{
			error in
			guard let openingError = error as? EditorOpeningError,
					case .invalidProject(let project) = openingError
			else
			{
				return false
			}
			return project == missingProject
		}

		let outside = outsideDirectory.appendingPathComponent("outside.swift")
		try await BackgroundTestWork.perform
		{
			try Data("outside".utf8).write(to: outside)
		}
		await #expect
		{
			try await editor.open(
				path: outside.path,
				project: root,
				line: 1
			)
		} throws:
		{
			error in
			guard let handoffError = error as? EditorOpeningError,
					case .outsideProject(let path) = handoffError
			else
			{
				return false
			}
			return path == outside.path
		}
		await #expect
		{
			try await editor.open(
				path: "deleted.swift",
				project: root,
				line: 1
			)
		} throws:
		{
			error in
			guard let handoffError = error as? EditorOpeningError,
					case .missingFile(let path) = handoffError
			else
			{
				return false
			}
			return path == "deleted.swift"
		}
	}

	@Test func symlinkEscapeIsRejected() async throws
	{
		let root = try await temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: root)
		}
		let outside = try await temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: outside)
		}
		let externalFile = outside.appendingPathComponent("outside.swift")
		try await BackgroundTestWork.perform
		{
			try Data("outside".utf8).write(to: externalFile)
			try FileManager.default.createSymbolicLink(
				at: root.appendingPathComponent("link.swift"),
				withDestinationURL: externalFile
			)
		}
		let defaultsFixture = try IsolatedUserDefaultsFixture(prefix: "EditorOpeningServiceTests")
		defer
		{
			defaultsFixture.cleanup()
		}
		let editor = EditorOpeningService(defaults: defaultsFixture.defaults)

		await #expect
		{
			try await editor.open(
				path: "link.swift",
				project: root,
				line: 1
			)
		} throws:
		{
			error in
			guard let handoffError = error as? EditorOpeningError,
					case .outsideProject(let path) = handoffError
			else
			{
				return false
			}
			return path == "link.swift"
		}
	}

	nonisolated private func temporaryDirectory() async throws -> URL
	{
		try await BackgroundTestWork.perform
		{
			let url = FileManager.default.temporaryDirectory
				.appendingPathComponent(
					"EditorOpeningServiceTests-\(UUID().uuidString)",
					isDirectory: true
				)
			try FileManager.default.createDirectory(
				at: url,
				withIntermediateDirectories: true
			)
			return url
		}
	}
}
