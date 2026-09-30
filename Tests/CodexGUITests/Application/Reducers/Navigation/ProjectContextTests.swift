import Foundation
import Testing

@testable import CodexGUI

@Suite("Project context")
struct ProjectContextTests
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

	@Test("Explicitly included items alone appear in request context")
	func contextSelection()
	{
		var context = ProjectContext()
		context.items = [
			ProjectContextItem(
				kind: .note,
				title: "Selected",
				body: "Send this",
				isIncluded: true
			),
			ProjectContextItem(
				kind: .decision,
				title: "Private",
				body: "Do not send"
			),
			ProjectContextItem(
				kind: .referenceFile,
				title: "Reference",
				referencePath: "docs/a.md",
				isIncluded: true
			),
		]
		#expect(context.includedContextText.contains("Send this"))
		#expect(context.includedContextText.contains("docs/a.md"))
		#expect(!context.includedContextText.contains("Do not send"))
	}

	@Test("Unreadable context is preserved rather than overwritten")
	@MainActor
	func corruptDataIsPreserved() throws
	{
		let directory = temporaryDirectory()
		let project = directory.appendingPathComponent("project")
		let store = ProjectContextStore(directory: directory)
		let file = store.fileURL(for: project)
		let original = Data("{broken".utf8)
		try FileManager.default.createDirectory(
			at: directory,
			withIntermediateDirectories: true
		)
		try original.write(to: file)

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

	@Test("Unsupported and wrong-project context bytes remain unchanged")
	@MainActor
	func protectedContextDocumentsArePreserved() async throws
	{
		for field in ["version", "projectPath"]
		{
			let directory = temporaryDirectory()
			defer
			{
				try? FileManager.default.removeItem(at: directory)
			}
			let project = directory.appendingPathComponent("project")
			let store = ProjectContextStore(directory: directory)
			try store.save(
				ProjectContext(),
				for: project
			)
			let file = store.fileURL(for: project)
			var document = try #require(
				JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
			)
			document[field] = field == "version" ? (999 as Any) : ("/another/project" as Any)
			let original = try JSONSerialization.data(withJSONObject: document)
			try original.write(to: file)
			#expect(throws: ProjectContextStoreError.self)
			{
				try store.load(for: project)
			}
			var edit = ProjectContext()
			edit.savedPrompts = [SavedPrompt(
				title: "Visible edit",
				instructions: "Keep me"
			)]
			#expect(throws: ProjectContextStoreError.self)
			{
				try store.save(
					edit,
					for: project
				)
			}
			#expect(try Data(contentsOf: file) == original)
			let workspace = WorkspaceStateStore(
				model: WorkspaceModel(identity: WorkspaceIdentity(
					sessionID: UUID(),
					canonicalCheckoutPath: project.standardizedFileURL.resolvingSymlinksInPath()
						.path
				)),
				service: AppServer(),
				persistence: WorkspacePersistenceScheduler(writeDraft:
					{
						_ in
					}),
				projectContextStore: store,
				reducers: [ContextNavigationReducer.reducer]
			)
			let save = ContextSaveOperation(
				context: workspace.operationContext(),
				revision: 1,
				value: edit
			)
			workspace.dispatch(.contextNavigation(.contextEdited(save)))
			#expect(workspace.model.contextNavigation.projectContext == edit)
			let handle = try #require(workspace.operation(for: save.context))
			_ = await handle.wait()
			#expect(workspace.model.contextNavigation.projectContext == edit)
			#expect(workspace.model.contextNavigation.contextError != nil)
			#expect(try Data(contentsOf: file) == original)
		}
	}

	@Test("Project alias shares context identity")
	@MainActor
	func symlinkIdentity() throws
	{
		let directory = temporaryDirectory()
		let project = directory.appendingPathComponent("project")
		let alias = directory.appendingPathComponent("alias")
		try FileManager.default.createDirectory(
			at: project,
			withIntermediateDirectories: true
		)
		try FileManager.default.createSymbolicLink(
			at: alias,
			withDestinationURL: project
		)
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

	@Test("Search shows loaded scope and stable references")
	func contentSearch() throws
	{
		let turn = try #require(
			CodexTurn(json: [
				"id": "turn-a",
				"status": "completed",
				"items": [
					[
						"id": "item-user",
						"type": "userMessage",
						"content": [["text": "Choose AppKit"]]
					],
					[
						"id": "item-agent",
						"type": "agentMessage",
						"text": "We chose AppKit for macOS."
					],
				],
			])
		)
		let thread = SearchableThread(
			threadID: "thread-a",
			title: "Architecture",
			turns: [turn],
			hasEarlierTurns: true
		)
		let results = MessageSearch.search(
			query: "appkit",
			threads: [thread],
			totalThreadCount: 3
		)

		#expect(results.hits.count == 2)
		#expect(results.hits[0].threadID == "thread-a")
		#expect(results.hits[0].turnID == "turn-a")
		#expect(results.hits[0].itemID == "item-user")
		#expect(results.scope.loadedThreadCount == 1)
		#expect(results.scope.totalThreadCount == 3)
		#expect(results.scope.threadsWithEarlierTurns == 1)
		#expect(results.scope.canLoadMore)
		#expect(results.scope.description.contains("earlier turns"))
	}

	@Test("Jump targets preserve item and changed-file references")
	func navigationReferences() throws
	{
		let turn = try #require(
			CodexTurn(json: [
				"id": "turn-a",
				"status": "failed",
				"error": ["message": "Request failed"],
				"items": [
					["id": "request", "type": "userMessage", "content": [["text": "Change file"]]],
					[
						"id": "patch",
						"type": "fileChange",
						"changes": [
							["path": "Sources/A.swift", "kind": "update", "diff": ""],
							["path": "Sources/B.swift", "kind": "update", "diff": ""],
						],
					],
				],
			])
		)
		let thread = SearchableThread(
			threadID: "thread-a",
			title: "Work",
			turns: [turn],
			hasEarlierTurns: false
		)
		let targets = ConversationNavigation.targets(in: thread)

		#expect(targets.count == 4)
		#expect(targets[0].itemID == "request")
		#expect(targets[1].itemID == "patch")
		#expect(targets[1].filePath == "Sources/A.swift")
		#expect(targets[2].filePath == "Sources/B.swift")
		#expect(targets[1].id != targets[2].id)
		#expect(targets[3].kind == .failure)
	}

	@Test("Coordinator keeps edits on save failure and never sends an inspected prompt")
	@MainActor
	func coordinatorCompositionAndSaveFailure() async throws
	{
		let directory = temporaryDirectory()
		try FileManager.default.createDirectory(
			at: directory,
			withIntermediateDirectories: true
		)
		let store = ProjectContextStore(directory: directory)
		let project = directory.appendingPathComponent("project")
		let file = store.fileURL(for: project)
		try Data("{broken".utf8).write(to: file)
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: project.standardizedFileURL.resolvingSymlinksInPath().path
		))
		model.connection.generation = 1
		let workspace = WorkspaceStateStore(
			model: model,
			service: AppServer(),
			persistence: WorkspacePersistenceScheduler(writeDraft:
				{
					_ in
				}),
			projectContextStore: store,
			reducers: [ContextNavigationReducer.reducer]
		)
		let load = ContextLoadOperation(
			context: workspace.operationContext(),
			revision: 0
		)
		workspace.dispatch(.contextNavigation(.contextLoadRequested(load)))
		let loadHandle = try #require(workspace.operation(for: load.context))
		_ = await loadHandle.wait()
		#expect(workspace.model.contextNavigation.contextError != nil)

		var context = workspace.model.contextNavigation.projectContext
		context.items = [
			ProjectContextItem(
				kind: .note,
				title: "Architecture",
				body: "Use AppKit",
				isIncluded: true
			),
			ProjectContextItem(
				kind: .note,
				title: "Not selected",
				body: "Private text"
			),
		]
		context.savedPrompts = [SavedPrompt(
			title: "Review",
			instructions: "Find regressions"
		)]
		context.selectedPromptID = context.savedPrompts[0].id
		let save = ContextSaveOperation(
			context: workspace.operationContext(),
			revision: 1,
			value: context
		)
		workspace.dispatch(.contextNavigation(.contextEdited(save)))
		let saveHandle = try #require(workspace.operation(for: save.context))
		_ = await saveHandle.wait()

		#expect(workspace.model.contextNavigation.contextError != nil)
		#expect(workspace.model.contextNavigation.projectContext == context)
		let request = ProjectProductivity.requestText(
			context: context,
			draft: "Implement it"
		)
		#expect(request.contains("Use AppKit"))
		#expect(!request.contains("Private text"))
		#expect(!request.contains("Find regressions"))
		#expect(
			ProjectProductivity.insertSavedPrompt(
				context: context,
				id: context.savedPrompts[0].id,
				into: "Implement it"
			)
				== "Implement it\n\nFind regressions"
		)
		#expect(try Data(contentsOf: file) == Data("{broken".utf8))
	}

	@Test("Coordinator resolves a selected skill only from the current enabled catalog")
	@MainActor
	func selectedSkillResolution() throws
	{
		var context = ProjectContext()
		context.selectedSkill = ProjectSkillSelection(
			name: "review",
			description: "Review code",
			path: "/old/review/SKILL.md"
		)
		let available = try #require(
			AvailableSkill(json: [
				"name": "review",
				"description": "Review code",
				"path": "/new/review/SKILL.md",
				"scope": "repo",
				"enabled": true,
			])
		)
		let catalog = SkillCatalog(
			skills: [available],
			errors: []
		)

		#expect(ProjectProductivity.resolvedSkill(
			context: context,
			in: catalog
		)?
			.path == "/new/review/SKILL.md")
		#expect(ProjectProductivity.skillWarning(
			context: context,
			in: catalog
		) == nil)
		#expect(ProjectProductivity.resolvedSkill(
			context: context,
			in: nil
		) == nil)
		#expect(ProjectProductivity.skillWarning(
			context: context,
			in: nil
		) != nil)
	}
}

private func temporaryDirectory() -> URL
{
	FileManager.default.temporaryDirectory.appendingPathComponent(
		UUID().uuidString,
		isDirectory: true
	)
}
