import Foundation
import Testing

@testable import CodexGUI

@Suite
@MainActor
struct ComposerContextStorageTests
{

	@Test func sentReferenceRetentionIsGloballyBoundedAcrossProjects() throws
	{
		let firstProject = try temporaryProject()
		let secondProject = try temporaryProject()
		defer
		{
			try? FileManager.default.removeItem(at: firstProject)
			try? FileManager.default.removeItem(at: secondProject)
		}
		let isolated = try IsolatedUserDefaultsFixture(prefix: "ComposerContextRetentionTests")
		defer
		{
			isolated.cleanup()
		}
		let storage = LocalStorage(defaults: isolated.defaults)
		func references(_ count: Int) -> [ComposerContextItem]
		{
			(0 ..< count).map
			{
				number in
				ComposerContextItem(
					kind: .textExcerpt,
					title: "Item \(number)",
					path: "File.swift",
					firstLine: number + 1,
					lastLine: number + 1,
					excerpt: "line"
				)
			}
		}
		storage.rememberSentReferences(
			references(80),
			for: firstProject,
			threadID: "one"
		)
		storage.rememberSentReferences(
			references(80),
			for: firstProject,
			threadID: "two"
		)
		storage.rememberSentReferences(
			references(60),
			for: secondProject,
			threadID: "three"
		)
		#expect(storage.sentReferences(
			for: firstProject,
			threadID: "one"
		).count == 60)
		#expect(storage.sentReferences(
			for: firstProject,
			threadID: "two"
		).count == 80)
		#expect(storage.sentReferences(
			for: secondProject,
			threadID: "three"
		).count == 60)
	}

	@Test func earlierSentReferenceFormatIsReadAndMigratedOnWrite() throws
	{
		let project = try temporaryProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let isolated = try IsolatedUserDefaultsFixture(prefix: "ComposerContextMigrationTests")
		defer
		{
			isolated.cleanup()
		}
		let original = ComposerContextItem(
			id: "legacy-file-reference",
			kind: .fileReference,
			title: "Old",
			path: "Old.swift"
		)
		let excerpt = ComposerContextItem(
			id: "legacy-text-excerpt",
			kind: .textExcerpt,
			title: "Earlier code",
			path: "Old.swift",
			firstLine: 4,
			lastLine: 5,
			excerpt: "let answer = 42"
		)
		// These historical keys and enum values must not follow the current Codable model.
		let legacyItems: [[String: Any]] = [
			[
				"id": "legacy-file-reference",
				"kind": "fileReference",
				"title": "Old",
				"path": "Old.swift"
			],
			[
				"id": "legacy-text-excerpt",
				"kind": "textExcerpt",
				"title": "Earlier code",
				"path": "Old.swift",
				"firstLine": 4,
				"lastLine": 5,
				"excerpt": "let answer = 42"
			]
		]
		let projectPath = project.standardizedFileURL.resolvingSymlinksInPath().path
		let legacy = [projectPath: ["thread:one": legacyItems]]
		let legacyData = try JSONSerialization.data(withJSONObject: legacy)
		isolated.defaults.set(
			legacyData,
			forKey: "CodexGUI.sentReferences"
		)
		let storage = LocalStorage(defaults: isolated.defaults)
		#expect(storage.sentReferences(
			for: project,
			threadID: "one"
		) == [original, excerpt])
		#expect(isolated.defaults.data(forKey: "CodexGUI.sentReferences") == legacyData)
		let next = ComposerContextItem(
			id: "new-file-reference",
			kind: .fileReference,
			title: "New",
			path: "New.swift"
		)
		storage.rememberSentReferences(
			[next],
			for: project,
			threadID: "one"
		)
		#expect(storage.sentReferences(
			for: project,
			threadID: "one"
		) == [original, excerpt, next])
		let migratedData = try #require(isolated.defaults.data(forKey: "CodexGUI.sentReferences"))
		let records = try #require(
			JSONSerialization.jsonObject(with: migratedData) as? [[String: Any]]
		)
		let expectedItems = legacyItems + [[
			"id": "new-file-reference",
			"kind": "fileReference",
			"title": "New",
			"path": "New.swift"
		]]
		let expectedRecords: [[String: Any]] = expectedItems.map
		{
			["projectPath": projectPath, "threadID": "one", "item": $0]
		}
		#expect(NSArray(array: records) == NSArray(array: expectedRecords))
	}

	private func ownedImage(in directory: URL) throws -> URL
	{
		let file = directory.appendingPathComponent("\(UUID().uuidString).png")
		try Data([1, 2, 3]).write(to: file)
		return file
	}

	private func temporaryProject() throws -> URL
	{
		let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(
			at: url,
			withIntermediateDirectories: true
		)
		return url
	}
}
