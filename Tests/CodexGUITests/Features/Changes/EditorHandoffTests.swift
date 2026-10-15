import AppKit
import Foundation
import Testing

@testable import CodexGUI

@Suite @MainActor
struct EditorHandoffTests
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
		let defaultsFixture = try IsolatedUserDefaultsFixture(prefix: "EditorHandoffTests")
		defer
		{
			defaultsFixture.cleanup()
		}
		let handoff = EditorHandoff(defaults: defaultsFixture.defaults)

		let outside = outsideDirectory.appendingPathComponent("outside.swift")
		try await BackgroundTestWork.perform
		{
			try Data("outside".utf8).write(to: outside)
		}
		await #expect
		{
			try await handoff.open(
				path: outside.path,
				project: root,
				diff: ""
			)
		} throws:
		{
			error in
			guard let handoffError = error as? EditorHandoffError,
					case .outsideProject(let path) = handoffError
			else
			{
				return false
			}
			return path == outside.path
		}
		await #expect
		{
			try await handoff.open(
				path: "deleted.swift",
				project: root,
				diff: ""
			)
		} throws:
		{
			error in
			guard let handoffError = error as? EditorHandoffError,
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
		let defaultsFixture = try IsolatedUserDefaultsFixture(prefix: "EditorHandoffTests")
		defer
		{
			defaultsFixture.cleanup()
		}
		let handoff = EditorHandoff(defaults: defaultsFixture.defaults)

		await #expect
		{
			try await handoff.open(
				path: "link.swift",
				project: root,
				diff: ""
			)
		} throws:
		{
			error in
			guard let handoffError = error as? EditorHandoffError,
					case .outsideProject(let path) = handoffError
			else
			{
				return false
			}
			return path == "link.swift"
		}
	}

	@Test func vscodeUsesBundledCLIWithGotoArgumentsAndPersistsPreference() async throws
	{
		let root = try await temporaryDirectory()
		let app = try await temporaryDirectory().appendingPathComponent("Fake Code.app")
		let defaultsFixture = try IsolatedUserDefaultsFixture(prefix: "EditorHandoffTests")
		defer
		{
			try? FileManager.default.removeItem(at: root)
			try? FileManager.default.removeItem(at: app.deletingLastPathComponent())
			defaultsFixture.cleanup()
		}
		// Fake editor installation and checkout files do not access AppKit state.
		let (file, captured) = try await BackgroundTestWork.perform
		{
			let file = root.appendingPathComponent("folder with spaces/file.swift")
			try FileManager.default.createDirectory(
				at: file.deletingLastPathComponent(),
				withIntermediateDirectories: true
			)
			try Data("content".utf8).write(to: file)

			let cli = app.appendingPathComponent("Contents/Resources/app/bin/code")
			try FileManager.default.createDirectory(
				at: cli.deletingLastPathComponent(),
				withIntermediateDirectories: true
			)
			let captured = root.appendingPathComponent("arguments.json")
			let capturedPathLiteral = String(
				decoding: try JSONSerialization.data(
					withJSONObject: captured.path,
					options: [
						.fragmentsAllowed,
						.withoutEscapingSlashes
					]
				),
				as: UTF8.self
			)
			let script = """
			#!/usr/bin/env python3
			import json, sys
			with open(\(capturedPathLiteral), "w") as output:
			    json.dump(sys.argv[1:], output)
			"""
			try Data(script.utf8).write(to: cli)
			try FileManager.default.setAttributes(
				[.posixPermissions: 0o755],
				ofItemAtPath: cli.path
			)
			let info: [String: Any] = [
				"CFBundleIdentifier": "com.microsoft.VSCode",
				"CFBundleName": "Fake Code",
				"CFBundlePackageType": "APPL",
			]
			let infoData = try PropertyListSerialization.data(
				fromPropertyList: info,
				format: .xml,
				options: 0
			)
			try FileManager.default.createDirectory(
				at: app.appendingPathComponent("Contents"),
				withIntermediateDirectories: true
			)
			try infoData.write(to: app.appendingPathComponent("Contents/Info.plist"))
			return (file, captured)
		}
		let handoff = EditorHandoff(defaults: defaultsFixture.defaults)
		handoff.preferredApplication = app
		#expect(
			EditorHandoff(defaults: defaultsFixture.defaults)
				.preferredApplication?.standardizedFileURL.path
				== app.standardizedFileURL.path
		)
		let diff = """
		@@ -3,2 +3,3 @@
		 context
		-old
		+new
		"""
		let note = try await handoff.open(
			path: file.path,
			project: root,
			diff: diff
		)
		#expect(note == nil)
		let capturedData = try await BackgroundTestWork.perform
		{
			try Data(contentsOf: captured)
		}
		let arguments = try JSONSerialization.jsonObject(with: capturedData) as? [String]
		#expect(arguments == ["--goto", "\(file.path):4"])
	}

	nonisolated private func temporaryDirectory() async throws -> URL
	{
		try await BackgroundTestWork.perform
		{
			let url = FileManager.default.temporaryDirectory
				.appendingPathComponent(
					"EditorHandoffTests-\(UUID().uuidString)",
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
