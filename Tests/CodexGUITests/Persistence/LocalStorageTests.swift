import Foundation
import Testing

@testable import CodexGUI

@Suite("Local storage")
struct LocalStorageTests
{
	@Test("Recent projects are unique, newest first, and limited to ten")
	@MainActor
	func recentProjectsAreUniqueNewestFirstAndLimited() throws
	{
		let storage = LocalStorage(defaults: try makeDefaults())
		let rootURL = temporaryRootURL()

		for projectIndex in 0 ..< 12
		{
			let projectURL = rootURL.appendingPathComponent("project-\(projectIndex)")
			storage.rememberProject(projectURL)
		}

		let newestProjectURL = rootURL.appendingPathComponent("project-11")
		storage.rememberProject(newestProjectURL)

		#expect(storage.recentProjects.count == 10)
		#expect(storage.recentProjects.first?.path == newestProjectURL.path)
		#expect(
			storage.recentProjects.last?.path == rootURL.appendingPathComponent("project-2").path
		)
		#expect(Set(storage.recentProjects.map(\.path)).count == 10)
	}

	@Test("Drafts are separated by project and conversation")
	@MainActor
	func draftsAreSeparatedByProjectAndConversation() throws
	{
		let storage = LocalStorage(defaults: try makeDefaults())
		let firstProjectURL = temporaryRootURL().appendingPathComponent("first-project")
		let secondProjectURL = temporaryRootURL().appendingPathComponent("second-project")

		storage.saveDraft(
			"new chat",
			for: firstProjectURL,
			threadID: nil
		)
		storage.saveDraft(
			"thread one",
			for: firstProjectURL,
			threadID: "thread-1"
		)
		storage.saveDraft(
			"thread two",
			for: firstProjectURL,
			threadID: "thread-2"
		)
		storage.saveDraft(
			"other project",
			for: secondProjectURL,
			threadID: "thread-1"
		)

		#expect(storage.draft(
			for: firstProjectURL,
			threadID: nil
		) == "new chat")
		#expect(storage.draft(
			for: firstProjectURL,
			threadID: "thread-1"
		) == "thread one")
		#expect(storage.draft(
			for: firstProjectURL,
			threadID: "thread-2"
		) == "thread two")
		#expect(storage.draft(
			for: secondProjectURL,
			threadID: "thread-1"
		) == "other project")
		#expect(storage.draft(
			for: firstProjectURL,
			threadID: "missing-thread"
		).isEmpty)
	}

	@Test("Project symlinks share recent project and draft identity")
	@MainActor
	func projectSymlinksShareRecentProjectAndDraftIdentity() throws
	{
		let storage = LocalStorage(defaults: try makeDefaults())
		let rootURL = temporaryRootURL()
		let projectURL = rootURL.appendingPathComponent(
			"project",
			isDirectory: true
		)
		let aliasURL = rootURL.appendingPathComponent(
			"project-alias",
			isDirectory: true
		)
		try FileManager.default.createDirectory(
			at: projectURL,
			withIntermediateDirectories: true
		)
		try FileManager.default.createSymbolicLink(
			at: aliasURL,
			withDestinationURL: projectURL
		)

		storage.rememberProject(projectURL)
		storage.saveDraft(
			"saved through original path",
			for: projectURL,
			threadID: nil
		)

		#expect(storage.recentProjects.count == 1)
		#expect(storage.draft(
			for: aliasURL,
			threadID: nil
		) == "saved through original path")
	}

	@Test("Legacy recent project and draft values are migrated")
	@MainActor
	func legacyRecentProjectAndDraftAreMigrated() throws
	{
		let defaults = try makeDefaults()
		let legacyProjectURL = temporaryRootURL().appendingPathComponent("legacy-project")
		defaults.set(
			legacyProjectURL.path,
			forKey: "recentProject"
		)
		defaults.set(
			"legacy draft",
			forKey: "draft"
		)

		let storage = LocalStorage(defaults: defaults)

		#expect(storage.recentProjects.first?.path == legacyProjectURL.path)
		#expect(storage.draft(
			for: legacyProjectURL,
			threadID: nil
		) == "legacy draft")
		#expect(defaults.object(forKey: "recentProject") == nil)
		#expect(defaults.object(forKey: "draft") == nil)
	}

	@Test("Last conversation is per project and explicit New Chat clears only its selection")
	@MainActor
	func selectedConversationPersistsPerProject() throws
	{
		let defaults = try makeDefaults()
		let first = temporaryRootURL().appendingPathComponent("first")
		let second = temporaryRootURL().appendingPathComponent("second")
		let storage = LocalStorage(defaults: defaults)
		storage.saveSelectedThreadID(
			"thread-a",
			for: first
		)
		storage.saveSelectedThreadID(
			"thread-b",
			for: second
		)
		storage.saveDraft(
			"keep me",
			for: first,
			threadID: "thread-a"
		)

		let reopened = LocalStorage(defaults: defaults)
		#expect(reopened.selectedThreadID(for: first) == "thread-a")
		#expect(reopened.selectedThreadID(for: second) == "thread-b")
		reopened.saveSelectedThreadID(
			nil,
			for: first
		)
		#expect(reopened.selectedThreadID(for: first) == nil)
		#expect(reopened.selectedThreadID(for: second) == "thread-b")
		#expect(reopened.draft(
			for: first,
			threadID: "thread-a"
		) == "keep me")
	}

	@Test("Model and effort selection survives reopening including explicit default")
	@MainActor
	func modelPreferencePersists() throws
	{
		let defaults = try makeDefaults()
		let storage = LocalStorage(defaults: defaults)
		#expect(storage.modelPreference == nil)
		storage.saveModelPreference(
			modelID: "model-old",
			effort: "high"
		)
		#expect(
			LocalStorage(defaults: defaults).modelPreference
				== LocalStorage.ModelPreference(
					modelID: "model-old",
					effort: "high"
				)
		)
		storage.saveModelPreference(
			modelID: nil,
			effort: nil
		)
		#expect(
			LocalStorage(defaults: defaults).modelPreference
				== LocalStorage.ModelPreference(
					modelID: nil,
					effort: nil
				)
		)
	}
}

private func makeDefaults() throws -> UserDefaults
{
	let suiteName = "LocalStorageTests.\(UUID().uuidString)"
	let defaults = try #require(UserDefaults(suiteName: suiteName))
	defaults.removePersistentDomain(forName: suiteName)
	return defaults
}

private func temporaryRootURL() -> URL
{
	FileManager.default.temporaryDirectory
		.appendingPathComponent(
			"LocalStorageTests-\(UUID().uuidString)",
			isDirectory: true
		)
}
