import Foundation
import Testing

@testable import CodexGUI

@Suite(
	"Project context storage"
)
struct ProjectContextStoreTests
{
	@Test("Project context survives reopening and stays in its project")
	@MainActor
	func persistsAcrossProjects() throws
	{
		let directory = temporaryDirectory()
		let first = directory.appendingPathComponent("first")
		let second = directory.appendingPathComponent("second")
		let store = ProjectContextStore(directory: directory.appendingPathComponent("data"))
		var context = ProjectContext()
		context.items = [
			ProjectContextItem(
				kind: .specification,
				title: "Spec",
				body: "Acceptance criteria"
			),
			ProjectContextItem(
				kind: .referenceFile,
				title: "Design",
				referencePath: "docs/missing.pdf"
			),
		]
		context.savedPrompts = [SavedPrompt(
			title: "Review",
			instructions: "Find regressions"
		)]
		context.selectedPromptID = context.savedPrompts[0].id
		context.selectedSkill = ProjectSkillSelection(
			name: "review",
			description: "Review code",
			path: "/skills/review/SKILL.md"
		)
		context.modelPreference = ProjectModelPreference(
			modelID: "test-model",
			effort: "high"
		)
		context.bookmarks = [
			ConversationBookmark(
				threadID: "thread-1",
				turnID: "turn-2",
				itemID: "item-3",
				kind: .decision,
				label: "Keep AppKit"
			)
		]
		try store.save(
			context,
			for: first
		)

		let reopened = ProjectContextStore(directory: directory.appendingPathComponent("data"))
		#expect(try reopened.load(for: first) == context)
		#expect(try reopened.load(for: second) == ProjectContext())
		#expect(try reopened.load(for: first).items[1].referencePath == "docs/missing.pdf")
		#expect(try reopened.load(for: first).selectedPrompt?.instructions == "Find regressions")
		#expect(try reopened.load(for: first).selectedSkill?.invocationText == "$review")
		#expect(try reopened.load(for: first).modelPreference?.effort == "high")
		#expect(try reopened.load(for: first).bookmarks[0].itemID == "item-3")
	}
	@Test("Unreadable context is preserved rather than overwritten")
	@MainActor
	func corruptDataIsPreserved() async throws
	{
		let directory = temporaryDirectory()
		let project = directory.appendingPathComponent("project")
		let store = ProjectContextStore(directory: directory)
		let file = store.fileURL(for: project)
		let original = Data("{broken".utf8)
		try await BackgroundTestWork.perform
		{
			try FileManager.default.createDirectory(
				at: directory,
				withIntermediateDirectories: true
			)
			try original.write(to: file)
		}

		#expect(throws: ProjectContextStoreError.self)
		{
			try store.load(for: project)
		}
		#expect(throws: ProjectContextStoreError.self)
		{
			try store.save(
				ProjectContext(),
				for: project
			)
		}
		#expect(try Data(contentsOf: file) == original)
	}
	@Test("Project alias shares context identity")
	@MainActor
	func symlinkIdentity() async throws
	{
		let directory = temporaryDirectory()
		let project = directory.appendingPathComponent("project")
		let alias = directory.appendingPathComponent("alias")
		try await BackgroundTestWork.perform
		{
			try FileManager.default.createDirectory(
				at: project,
				withIntermediateDirectories: true
			)
			try FileManager.default.createSymbolicLink(
				at: alias,
				withDestinationURL: project
			)
		}
		let store = ProjectContextStore(directory: directory.appendingPathComponent("data"))
		var context = ProjectContext()
		context.modelPreference = ProjectModelPreference(
			modelID: nil,
			effort: nil
		)
		try store.save(
			context,
			for: project
		)

		#expect(store.fileURL(for: alias) == store.fileURL(for: project))
		#expect(try store.load(for: alias).modelPreference == context.modelPreference)
	}

	private func temporaryDirectory() -> URL
	{
		FileManager.default.temporaryDirectory.appendingPathComponent(
			UUID().uuidString,
			isDirectory: true
		)
	}
}
