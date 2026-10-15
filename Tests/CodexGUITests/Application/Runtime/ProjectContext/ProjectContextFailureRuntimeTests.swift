import Foundation
import Testing

@testable import CodexGUI

@Suite(
	"Project context failure runtime"
)
struct ProjectContextFailureRuntimeTests
{
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

	private func temporaryDirectory() -> URL
	{
		FileManager.default.temporaryDirectory.appendingPathComponent(
			UUID().uuidString,
			isDirectory: true
		)
	}
}
